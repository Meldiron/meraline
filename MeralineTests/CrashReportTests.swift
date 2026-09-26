import Foundation
import Testing
@testable import Meraline

@MainActor
struct CrashReportTests {
    private static let bundleID = "com.meldiron.meraline"
    private static let secret = "What is my password?"
    private static let base: UInt64 = 0x1_0089_4000

    /// A report as macOS writes it: a line of JSON about the incident, then the report.
    private func ips(
        bundleID: String = bundleID,
        bugType: String = "309",
        asi: [String: [String]] = ["libswiftCore.dylib": ["Meraline/ChatSession.swift:120: Fatal error: Duplicate values for key: '\(secret)'"]],
        exceptionBacktrace: [[String: Any]]? = nil
    ) throws -> String {
        let header: [String: Any] = [
            "app_name": "Meraline", "timestamp": "2026-09-26 10:00:05.00 +0200", "app_version": "1.4.0", "build_version": "321",
            "bundleID": bundleID, "bug_type": bugType, "name": "Meraline", "incident_id": "EC3412BE-02B6-46CB-8A79-4956DEF62651",
        ]
        var body: [String: Any] = [
            "procLaunch": "2026-09-26 10:00:00.2478 +0200",
            "captureTime": "2026-09-26 10:00:05.1234 +0200",
            "procPath": "/Applications/Meraline.app/Contents/MacOS/Meraline",
            "crashReporterKey": "CRASH-REPORTER-KEY",
            "storeInfo": ["deviceIdentifierForVendor": "DEVICE-IDENTIFIER"],
            "exception": ["type": "EXC_BREAKPOINT", "signal": "SIGTRAP", "codes": "0x1, 0x2"],
            "termination": ["namespace": "SIGNAL", "indicator": "Trace/BPT trap: 5", "code": 5, "byProc": "exc handler"],
            "asi": asi,
            "faultingThread": 0,
            "threads": [
                [
                    "triggered": true, "queue": "com.apple.main-thread", "threadState": ["x": [["value": 987_654_321]]],
                    "frames": [
                        ["imageOffset": 1000, "symbol": "_assertionFailure(_:_:file:line:flags:)", "symbolLocation": 44, "imageIndex": 1],
                        ["imageOffset": 23460, "imageIndex": 0],
                    ],
                ],
                ["frames": [["imageOffset": 8, "imageIndex": 1]]],
            ],
            "usedImages": [
                ["arch": "arm64", "base": Self.base, "uuid": "405c6aef-9576-3c90-a775-a6d84a429a76", "path": "/Applications/Meraline.app/Contents/MacOS/Meraline", "name": "Meraline"],
                ["arch": "arm64e", "base": 0x1_8000_0000, "uuid": "74e52480-c2bd-3c8d-812d-95fe2b74a096", "path": "/usr/lib/swift/libswiftCore.dylib", "name": "libswiftCore.dylib"],
                ["size": 0, "source": "A", "base": 0, "uuid": "00000000-0000-0000-0000-000000000000"],
            ],
        ]
        if let exceptionBacktrace { body["lastExceptionBacktrace"] = exceptionBacktrace }
        let headerLine = String(decoding: try JSONSerialization.data(withJSONObject: header), as: UTF8.self)
        let bodyText = String(decoding: try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted), as: UTF8.self)
        return headerLine + "\n" + bodyText
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CrashReportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ text: String, named name: String, in folder: URL, modified: Date) throws {
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    @Test func readsHowAndWhereItCrashed() throws {
        let report = try #require(CrashReport(ips: try ips(), bundleID: Self.bundleID))
        #expect(report.version == "1.4.0")
        #expect(report.build == "321")
        #expect(report.exception == "EXC_BREAKPOINT (SIGTRAP)")
        #expect(report.termination == ["SIGNAL, Trace/BPT trap: 5"])
        #expect(report.message == "Meraline/ChatSession.swift:120: Fatal error: Duplicate values for key")
        #expect(report.image == "Meraline arm64 405C6AEF-9576-3C90-A775-A6D84A429A76 at 0x\(String(Self.base, radix: 16))")
        #expect(report.thread == "Crashed thread 0 (com.apple.main-thread)")
        #expect(report.frames.count == 2)
        #expect(report.frames[0].hasPrefix("0   libswiftCore.dylib"))
        #expect(report.frames[0].hasSuffix("_assertionFailure(_:_:file:line:flags:) + 44"))
        // Without symbols, a frame says where it falls in its image, for reading it with the dSYMs.
        #expect(report.frames[1].hasSuffix("0x\(String(Self.base + 23460, radix: 16)) 0x\(String(Self.base, radix: 16)) + 23460"))
        #expect(report.exceptionFrames.isEmpty)
        let ran = try #require(report.crashed.flatMap { crashed in report.launched.map { crashed.timeIntervalSince($0) } })
        #expect(abs(ran - 4.8756) < 0.001)
        #expect(report.summary[0] == "- Meraline 1.4.0 (321) quit unexpectedly at 2026-09-26T08:00:05Z, 4.9 s after it launched")
    }

    @Test func keepsNothingThatMayQuoteAValue() throws {
        let swift = try #require(CrashReport(ips: try ips(), bundleID: Self.bundleID))
        let exception = try #require(CrashReport(
            ips: try ips(
                asi: ["CoreFoundation": [
                    "*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '\(Self.secret)'",
                    "terminating with uncaught exception of type NSException",
                ]],
                exceptionBacktrace: [["imageOffset": 12, "symbol": "__exceptionPreprocess", "symbolLocation": 164, "imageIndex": 1]]
            ),
            bundleID: Self.bundleID
        ))
        #expect(exception.message == "Uncaught exception NSInvalidArgumentException")
        #expect(exception.exceptionFrames.count == 1)

        for report in [swift, exception] {
            let summary = report.summary.joined(separator: "\n")
            #expect(!summary.contains(Self.secret))
            #expect(!summary.contains("CRASH-REPORTER-KEY"))
            #expect(!summary.contains("DEVICE-IDENTIFIER"))
            #expect(!summary.contains("987654321"))
        }
        #expect(exception.summary.contains("Last exception backtrace:"))
    }

    @Test func swiftMessagesKeepTheRuntimesWordsOnly() {
        #expect(CrashReport.message(from: ["libswiftCore.dylib": ["Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range"]])
            == "Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range")
        // What a thrown error says, and anything quoted, may be a value.
        #expect(CrashReport.message(from: ["libswiftCore.dylib": ["Meraline/Rewrite.swift:12: Fatal error: 'try!' expression unexpectedly raised an error: \(Self.secret)"]])
            == "Meraline/Rewrite.swift:12: Fatal error")
        #expect(CrashReport.message(from: ["libswiftCore.dylib": ["Meraline/Game.swift:3: Precondition failed"]]) == "Meraline/Game.swift:3: Precondition failed")
        #expect(CrashReport.message(from: ["libsystem_c.dylib": ["abort() called"]]) == nil)
    }

    @Test func readsOnlyMeralinesCrashes() throws {
        #expect(CrashReport(ips: try ips(bundleID: "com.example.other"), bundleID: Self.bundleID) == nil)
        // A hang or a resource report has another bug type.
        #expect(CrashReport(ips: try ips(bugType: "288"), bundleID: Self.bundleID) == nil)
        #expect(CrashReport(ips: "not a report", bundleID: Self.bundleID) == nil)
    }

    @Test func findsTheNewestCrashSinceADate() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let launch = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try write(try ips(), named: "Meraline-before.ips", in: folder, modified: launch.addingTimeInterval(-60))
        try write(try ips(asi: [:]), named: "Meraline-after.ips", in: folder, modified: launch.addingTimeInterval(60))
        try write(try ips(bundleID: "com.example.other"), named: "Meraline-newest.ips", in: folder, modified: launch.addingTimeInterval(120))
        try write(try ips(), named: "Other-newest.ips", in: folder, modified: launch.addingTimeInterval(120))

        let report = CrashReport.latest(in: [folder, folder.appending(path: "Retired")], since: launch, bundleID: Self.bundleID, process: "Meraline")
        #expect(report?.message == nil)
        #expect(report?.version == "1.4.0")
        #expect(CrashReport.latest(in: [folder], since: launch.addingTimeInterval(90), bundleID: Self.bundleID, process: "Meraline") == nil)
    }

    @Test func offersTheCrashOnceAfterIt() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = makeDefaults()
        let first = Date(timeIntervalSinceReferenceDate: 800_000_000)
        // A report from before the first launch that knows this is never offered.
        try write(try ips(bundleID: Bundle.main.bundleIdentifier ?? Self.bundleID), named: "\(ProcessInfo.processInfo.processName)-old.ips", in: folder, modified: first.addingTimeInterval(-60))

        let firstLaunch = CrashNotice(defaults: defaults, folders: [folder])
        firstLaunch.checkForCrash(now: first)
        #expect(!firstLaunch.isOffered)

        try write(try ips(bundleID: Bundle.main.bundleIdentifier ?? Self.bundleID), named: "\(ProcessInfo.processInfo.processName)-crash.ips", in: folder, modified: first.addingTimeInterval(60))
        let afterCrash = CrashNotice(defaults: defaults, folders: [folder])
        afterCrash.checkForCrash(now: first.addingTimeInterval(120))
        #expect(afterCrash.isOffered)
        #expect(afterCrash.crash?.version == "1.4.0")
        afterCrash.dismiss()
        #expect(!afterCrash.isOffered)
        // Settings' Copy Diagnostics still includes it for the rest of the run.
        #expect(afterCrash.crash != nil)

        let next = CrashNotice(defaults: defaults, folders: [folder])
        next.checkForCrash(now: first.addingTimeInterval(180))
        #expect(!next.isOffered)
        #expect(next.crash == nil)
    }

    @Test func diagnosticsIncludeTheCrash() throws {
        let preferences = Preferences(defaults: makeDefaults(), secrets: SecretStore(read: { _ in "" }, write: { _, _ in }))
        let updates = Diagnostics.UpdateStatus(isAvailable: false, channel: .stable, checksAutomatically: false, downloadsAutomatically: false, lastCheck: nil, state: "idle")
        let crash = try #require(CrashReport(ips: try ips(), bundleID: Self.bundleID))

        let report = Diagnostics.report(preferences: preferences, updates: updates, entries: [], crash: crash)
        #expect(report.contains("### Crash"))
        #expect(report.contains("- Exception: EXC_BREAKPOINT (SIGTRAP)"))
        #expect(!report.contains(Self.secret))
        #expect(!Diagnostics.report(preferences: preferences, updates: updates, entries: [], crash: nil).contains("### Crash"))
    }
}
