import Foundation
import Testing
@testable import Meraline

@MainActor
struct PreferencesTests {
    private let noSecrets = SecretStore(read: { _ in "" }, write: { _, _ in })

    private func makeDefaults() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func providerReadiness() {
        let keyed = ProviderSettings(model: "m", baseURL: "https://x", apiKey: "", isEnabled: false)
        #expect(!keyed.isReady(for: .anthropic))
        #expect(ProviderSettings(model: "m", baseURL: "https://x", apiKey: "k", isEnabled: false).isReady(for: .anthropic))
        #expect(!keyed.isReady(for: .ollama))
        #expect(ProviderSettings(model: "m", baseURL: "http://x", apiKey: "", isEnabled: true).isReady(for: .ollama))
        #expect(!ProviderSettings(model: " ", baseURL: "http://x", apiKey: "", isEnabled: true).isReady(for: .custom))
    }

    @Test func enablingALocalProviderMakesItActive() {
        let preferences = Preferences(defaults: makeDefaults(), secrets: noSecrets)
        #expect(preferences.activeProvider == nil)

        var ollama = preferences[.ollama]
        ollama.isEnabled = true
        preferences[.ollama] = ollama

        #expect(preferences.activeProvider == .ollama)
        #expect(preferences.readyProviders == [.ollama])
    }

    @Test func settingsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets)
        var ollama = preferences[.ollama]
        ollama.isEnabled = true
        ollama.model = "qwen3"
        preferences[.ollama] = ollama
        preferences.placement = .pointer
        preferences.systemPrompt = "Custom"

        let reloaded = Preferences(defaults: defaults, secrets: noSecrets)
        #expect(reloaded[.ollama].model == "qwen3")
        #expect(reloaded.activeProvider == .ollama)
        #expect(reloaded.placement == .pointer)
        #expect(reloaded.systemPrompt == "Custom")
    }

    @Test func disablingTheActiveProviderClearsIt() {
        let preferences = Preferences(defaults: makeDefaults(), secrets: noSecrets)
        var ollama = preferences[.ollama]
        ollama.isEnabled = true
        preferences[.ollama] = ollama
        ollama.isEnabled = false
        preferences[.ollama] = ollama
        #expect(preferences.provider == nil)
    }

    @Test func markdownRendersInlineFormatting() {
        let rendered = MarkdownText.render("Use **bold** and `code`")
        #expect(String(rendered.characters) == "Use bold and code")
    }
}
