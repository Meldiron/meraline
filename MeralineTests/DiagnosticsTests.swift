import Foundation
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
