import AppKit
import Testing
@testable import Meraline

@MainActor
struct DiagnosticsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func reportDescribesSetupWithoutSecrets() {
        let secret = "sk-ant-THIS-MUST-NOT-LEAK"
        let secrets = SecretStore(read: { $0 == Provider.anthropic.rawValue ? secret : "" }, write: { _, _ in })
        let preferences = Preferences(defaults: makeDefaults(), secrets: secrets)
        var anthropic = preferences[.anthropic]
        anthropic.model = "claude-opus-5"
        preferences[.anthropic] = anthropic

        let entries = [
            LogEntry(date: .now, category: "chat", level: .info, message: "Asking Anthropic (claude-opus-5), turn 1, 0 image(s)")
        ]
        let report = Diagnostics.report(
            preferences: preferences,
            updates: .init(isAvailable: true, channel: .beta, checksAutomatically: true, downloadsAutomatically: false, lastCheck: nil, state: "up to date"),
            entries: entries
        )

        #expect(!report.contains(secret))
        #expect(report.contains("| Anthropic | ready | claude-opus-5 | api.anthropic.com |"))
        #expect(report.contains("beta channel"))
        #expect(report.contains("Mode: LLM, default LLM: Anthropic, default agent: none"))
        #expect(report.contains("[chat] info: Asking Anthropic"))
        #expect(!report.contains(NSHomeDirectory()))
    }

    // MARK: Redaction

    @Test func redactsTheHomeFolderAndKeys() {
        let text = "Running /Users/ann/.local/bin/claude in /Users/ann, not /Users/anna/x; sent sk-ant-12345678 and sk-ant-12345678-long"
        let redacted = Diagnostics.redacting(text, keys: ["sk-ant-12345678", " sk-ant-12345678-long ", ""], home: "/Users/ann")
        #expect(redacted == "Running ~/.local/bin/claude in ~, not /Users/anna/x; sent [key] and [key]")
    }

    @Test func theLogIsRedactedToo() {
        let secret = "sk-ant-THIS-MUST-NOT-LEAK"
        let secrets = SecretStore(read: { $0 == Provider.anthropic.rawValue ? secret : "" }, write: { _, _ in })
        let preferences = Preferences(defaults: makeDefaults(), secrets: secrets)
        let entries = [
            LogEntry(date: .now, category: "cli", level: .info, message: "Running \(NSHomeDirectory())/.local/bin/claude for Claude Code"),
            LogEntry(date: .now, category: "chat", level: .error, message: "Answer failed: Unauthorized (401): invalid x-api-key \(secret)"),
        ]
        let report = Diagnostics.report(preferences: preferences, updates: Self.updates, entries: entries)
        #expect(report.contains("[cli] info: Running ~/.local/bin/claude for Claude Code"))
        #expect(report.contains("invalid x-api-key [key]"))
        #expect(!report.contains(secret))
        #expect(!report.contains(NSHomeDirectory()))
    }

    // MARK: On demand

    private static let updates = Diagnostics.UpdateStatus(isAvailable: false, channel: .stable, checksAutomatically: false, downloadsAutomatically: false, lastCheck: nil, state: "idle")

    @Test func theSparkleCopiesDiagnosticsAtAnyTime() throws {
        let preferences = GameTestSupport.preferences()
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        let layout = PanelLayout()
        let withoutIt = PanelContext(session: session, preferences: preferences, layout: layout, openSettings: { _ in })
        #expect(!withoutIt.providersMenu.actions.contains { $0.id == "copyDiagnostics" })

        var copies = 0
        let context = PanelContext(session: session, preferences: preferences, layout: layout, openSettings: { _ in }, copyDiagnostics: { copies += 1 })
        let menu = context.providersMenu
        let row = try #require(menu.actions.first { $0.id == "copyDiagnostics" })
        #expect(row.title == "Copy Diagnostics")
        #expect(row.subtitle == "No questions, answers, or keys")
        #expect(menu.actions.last?.id == "copyDiagnostics")
        #expect(menu.filtered(by: "bug").flatMap(\.actions).map(\.id) == ["copyDiagnostics"])

        layout.actionPanel = ActionPanelRequest(kind: .providers)
        context.run(row, in: .providers)
        #expect(copies == 1)
        #expect(layout.actionPanel == nil)
    }

    @Test func diagnosticsCopiedMidChatHoldNoneOfIt() async throws {
        let preferences = GameTestSupport.preferences()
        let model = ScriptedModel(["It is PURPLE-OKAPI.", "Still PURPLE-OKAPI."])
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        session.bring(try #require(SelectedText("Quoted QUOTE-MARKER", appName: "Notes")))
        await GameTestSupport.play("What is QUESTION-MARKER?", in: session)
        session.reset()
        await GameTestSupport.play("And FOLLOW-MARKER?", in: session)

        let board = NSPasteboard(name: .init("MeralineTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let notice = CrashNotice(defaults: makeDefaults(), folders: [], pasteboard: board)
        #expect(!notice.isOffered)
        await notice.copyDiagnostics(of: session, preferences: preferences, updates: Self.updates)

        let report = try #require(board.string(forType: .string))
        #expect(report.hasPrefix("## Meraline diagnostics"))
        #expect(report.contains("- Chats in memory: an open chat of 1 turn(s) and 1 recent"))
        #expect(!report.contains("### Crash"))
        for content in ["PURPLE-OKAPI", "QUOTE-MARKER", "QUESTION-MARKER", "FOLLOW-MARKER"] {
            #expect(!report.contains(content), "\(content) reached the diagnostics")
        }

        // With no crash to offer, the capsule shows only to say Copied, then goes.
        #expect(notice.isOffered)
        #expect(notice.isCopied)
        let deadline = Date.now.addingTimeInterval(5)
        while notice.isOffered, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!notice.isOffered)
    }

    @Test func bufferKeepsOnlyTheNewestEntries() {
        let buffer = LogBuffer(capacity: 3)
        for index in 1...5 {
            buffer.append(LogEntry(date: .now, category: "test", level: .debug, message: "\(index)"))
        }
        #expect(buffer.entries.map(\.message) == ["3", "4", "5"])
        buffer.removeAll()
        #expect(buffer.entries.isEmpty)
    }
}
