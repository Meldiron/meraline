import Foundation

/// A crash of Meraline, read from the report macOS writes to ~/Library/Logs/DiagnosticReports when an app quits
/// unexpectedly. Meraline writes nothing itself; it only reads macOS's report, and keeps only what says how and
/// where it crashed: the exception, the termination, the Swift runtime's message or the uncaught exception's name,
/// and the crashed thread's frames. Nothing that may quote a value is kept (an exception's reason, what a Swift
/// message says after its first colon), nor the registers, the memory, or the identifiers of the Mac, so the
/// diagnostics that include it still hold no question, answer, or key.
nonisolated struct CrashReport: Sendable, Equatable {
    /// How many frames of a backtrace the report keeps.
    static let frameLimit = 40

    let version: String
    let build: String
    let launched: Date?
    let crashed: Date?
    /// "EXC_BAD_ACCESS (SIGSEGV), KERN_INVALID_ADDRESS at 0x0000000000000010".
    let exception: String?
    /// "SIGNAL, Trace/BPT trap: 5", then the reasons macOS gives, one per line.
    let termination: [String]
    /// "Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range", or "Uncaught exception NSRangeException".
    let message: String?
    /// Where Meraline's code was loaded, for reading its frames with the release's dSYMs: "Meraline arm64 <UUID> at 0x100890000".
    let image: String?
    let path: String?
    /// The crashed thread, "Crashed thread 0 (com.apple.main-thread)", and its frames.
    let thread: String
    let frames: [String]
    /// Where an uncaught exception was thrown, which the crashed thread no longer shows.
    let exceptionFrames: [String]

    /// Reads an `.ips` report: a line of JSON about the incident, then the report as JSON. Nil for another app's
    /// report, or one that isn't a crash (hangs and resource reports have another bug type).
    init?(ips: String, bundleID: String?) {
        let parts = ips.split(separator: "\n", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: Data(parts[0].utf8)),
              header.bugType == "309",
              bundleID == nil || header.bundleID == bundleID,
              let body = try? decoder.decode(Body.self, from: Data(parts[1].utf8)) else { return nil }

        version = header.appVersion ?? "unknown"
        build = header.buildVersion ?? "unknown"
        launched = Self.date(body.procLaunch)
        crashed = Self.date(body.captureTime ?? header.timestamp)
        exception = body.exception.flatMap { exception in
            guard let type = exception.type else { return nil }
            return type + (exception.signal.map { " (\($0))" } ?? "") + (exception.subtype.map { ", \($0)" } ?? "")
        }
        termination = body.termination.map { termination in
            let head = [termination.namespace, termination.indicator].compactMap { $0 }.joined(separator: ", ")
            let reasons = ((termination.reasons ?? []) + (termination.details ?? [])).prefix(6).map { Self.clip(Self.redactingHome($0), to: 300) }
            return (head.isEmpty ? [] : [head]) + reasons
        } ?? []
        message = body.asi.flatMap(Self.message(from:))

        let images = body.usedImages ?? []
        let main = images.first { $0.path != nil && $0.path == body.procPath }
        image = main.map { image in
            [image.name, image.arch, image.uuid?.uppercased(), image.base.map { "at 0x\(String($0, radix: 16))" }]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        path = body.procPath.map(Self.redactingHome)

        let threads = body.threads ?? []
        let index = body.faultingThread ?? threads.firstIndex { $0.triggered == true }
        let crashedThread = index.flatMap { threads.indices.contains($0) ? threads[$0] : nil }
        thread = "Crashed thread \(index.map(String.init) ?? "?")" + (crashedThread?.queue.map { " (\($0))" } ?? "")
        frames = Self.describe(crashedThread?.frames ?? [], images: images)
        exceptionFrames = Self.describe(body.lastExceptionBacktrace ?? [], images: images)
    }

    /// The report's section for the diagnostics, in Markdown.
    var summary: [String] {
        var lines: [String] = []
        let when = crashed.map { " at \($0.formatted(.iso8601))" } ?? ""
        var ran = ""
        if let launched, let crashed {
            // The same in every locale, like the rest of the report.
            let interval = max(0, crashed.timeIntervalSince(launched))
            let seconds = Int(interval)
            let duration = interval < 60 ? String(format: "%.1f s", interval) : String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            ran = ", \(duration) after it launched"
        }
        lines.append("- Meraline \(version) (\(build)) quit unexpectedly\(when)\(ran)")
        if let exception { lines.append("- Exception: \(exception)") }
        if let head = termination.first { lines.append("- Termination: \(head)") }
        for reason in termination.dropFirst() { lines.append("  - \(reason)") }
        if let message { lines.append("- Message: \(message)") }
        if let image { lines.append("- Image: \(image)") }
        if let path { lines.append("- Ran from \(path)") }
        lines.append("- The log of the run that crashed went with it; the log below is from this run.")
        if !exceptionFrames.isEmpty {
            lines.append("")
            lines.append("Last exception backtrace:")
            lines.append("```")
            lines.append(contentsOf: exceptionFrames)
            lines.append("```")
        }
        lines.append("")
        lines.append("\(thread):")
        lines.append("```")
        lines.append(contentsOf: frames.isEmpty ? ["(no frames)"] : frames)
        lines.append("```")
        return lines
    }

    /// Where macOS keeps the reports; it moves older ones into Retired.
    static var folders: [URL] {
        let reports = URL.libraryDirectory.appending(path: "Logs/DiagnosticReports", directoryHint: .isDirectory)
        return [reports, reports.appending(path: "Retired", directoryHint: .isDirectory)]
    }

    /// The newest report of Meraline crashing that macOS wrote after `date`, if any.
    static func latest(
        in folders: [URL] = folders,
        since date: Date,
        bundleID: String? = Bundle.main.bundleIdentifier,
        process: String = ProcessInfo.processInfo.processName
    ) -> CrashReport? {
        let files = folders
            .flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] }
            .filter { $0.lastPathComponent.hasPrefix(process) && $0.pathExtension == "ips" }
            .compactMap { url -> (url: URL, modified: Date)? in
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified > date else { return nil }
                return (url, modified)
            }
            .sorted { $0.modified > $1.modified }
        return files.lazy.compactMap { file in
            (try? String(contentsOf: file.url, encoding: .utf8)).flatMap { CrashReport(ips: $0, bundleID: bundleID) }
        }.first
    }

    /// The Swift runtime's fatal error, or the name of an uncaught Objective-C exception. A Swift message keeps its
    /// words up to the first colon, since what follows may be a value (a duplicate key, a thrown error), and none
    /// of them if they quote something; an exception keeps its name and never its reason.
    static func message(from notes: [String: [String]]) -> String? {
        let lines = notes.sorted { $0.key < $1.key }.flatMap(\.value).flatMap { $0.split(separator: "\n").map(String.init) }
        for line in lines {
            for prefix in ["Fatal error", "Precondition failed", "Assertion failed"] {
                guard let range = line.range(of: prefix) else { continue }
                let location = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":")))
                var words = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if words.hasPrefix(":") { words = String(words.dropFirst()).trimmingCharacters(in: .whitespaces) }
                if let colon = words.range(of: ":") { words = String(words[..<colon.lowerBound]) }
                if words.contains(where: { "'\"‘’“”`".contains($0) }) { words = "" }
                let place = location.isEmpty ? "" : redactingHome(location) + ": "
                return place + prefix + (words.isEmpty ? "" : ": " + clip(words, to: 120))
            }
        }
        for line in lines {
            guard let start = line.range(of: "uncaught exception '") else { continue }
            let name = line[start.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { return "Uncaught exception \(name)" }
        }
        return nil
    }

    /// Frames as macOS's own crash reports list them: number, image, address, then the symbol, or where the
    /// address falls in its image when the image carries no symbols.
    private static func describe(_ frames: [Frame], images: [Image]) -> [String] {
        frames.prefix(frameLimit).enumerated().map { number, frame in
            let image = frame.imageIndex.flatMap { images.indices.contains($0) ? images[$0] : nil }
            let name = image?.name ?? "???"
            let base = image?.base ?? 0
            let offset = frame.imageOffset ?? 0
            let place = frame.symbol.map { "\($0) + \(frame.symbolLocation ?? 0)" } ?? "0x\(String(base, radix: 16)) + \(offset)"
            let column = name.count < 30 ? name + String(repeating: " ", count: 30 - name.count) : name + " "
            let numberColumn = String(number) + String(repeating: " ", count: max(1, 4 - String(number).count))
            return "\(numberColumn)\(column)0x\(String(base &+ offset, radix: 16)) \(place)"
        }
    }

    /// "2026-09-25 16:44:08.2478 +0200", whose fraction of a second has as many digits as it likes.
    private static func date(_ text: String?) -> Date? {
        let parts = text?.split(separator: " ") ?? []
        guard parts.count == 3 else { return nil }
        let time = parts[1].split(separator: ".", maxSplits: 1)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        guard let date = formatter.date(from: "\(parts[0]) \(time[0]) \(parts[2])") else { return nil }
        return date.addingTimeInterval(time.count == 2 ? Double("0.\(time[1])") ?? 0 : 0)
    }

    private static func clip(_ text: String, to length: Int) -> String {
        text.count > length ? text.prefix(length) + "…" : text
    }

    /// The home folder as `~`, wherever it appears: a dyld reason names every path it tried.
    private static func redactingHome(_ text: String) -> String {
        let home = NSHomeDirectory()
        return text == home ? "~" : text.replacingOccurrences(of: home + "/", with: "~/")
    }

    // What the report reads of the `.ips` JSON; everything else in it is ignored.

    private struct Header: Decodable {
        let bugType: String?
        let bundleID: String?
        let appVersion: String?
        let buildVersion: String?
        let timestamp: String?

        enum CodingKeys: String, CodingKey {
            case bugType = "bug_type", bundleID, appVersion = "app_version", buildVersion = "build_version", timestamp
        }
    }

    private struct Body: Decodable {
        let procLaunch: String?
        let captureTime: String?
        let procPath: String?
        let exception: Exception?
        let termination: Termination?
        let asi: [String: [String]]?
        let faultingThread: Int?
        let threads: [Thread]?
        let lastExceptionBacktrace: [Frame]?
        let usedImages: [Image]?
    }

    private struct Exception: Decodable {
        let type: String?
        let signal: String?
        let subtype: String?
    }

    private struct Termination: Decodable {
        let namespace: String?
        let indicator: String?
        let reasons: [String]?
        let details: [String]?
    }

    private struct Thread: Decodable {
        let triggered: Bool?
        let queue: String?
        let frames: [Frame]?
    }

    private struct Frame: Decodable {
        let imageOffset: UInt64?
        let imageIndex: Int?
        let symbol: String?
        let symbolLocation: UInt64?
    }

    private struct Image: Decodable {
        let name: String?
        let arch: String?
        let uuid: String?
        let base: UInt64?
        let path: String?
    }
}
