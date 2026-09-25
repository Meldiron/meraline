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
        #expect(ProviderSettings(model: "", baseURL: "", apiKey: "", isEnabled: true).isReady(for: .apple))
        #expect(!ProviderSettings(model: "", baseURL: "", apiKey: "", isEnabled: false).isReady(for: .apple))
    }

    @Test func enablingALocalProviderMakesItActive() {
        let preferences = Preferences(defaults: makeDefaults(), secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(preferences.activeProvider == nil)

        var ollama = preferences[.ollama]
        ollama.isEnabled = true
        preferences[.ollama] = ollama

        #expect(preferences.activeProvider == .ollama)
        #expect(preferences.readyProviders == [.ollama])
    }

    @Test func updateChannelPersists() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets)
        #expect(preferences.updateChannel == .stable)
        preferences.updateChannel = .beta
        #expect(Preferences(defaults: defaults, secrets: noSecrets).updateChannel == .beta)
    }

    @Test func settingsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        var ollama = preferences[.ollama]
        ollama.isEnabled = true
        ollama.model = "qwen3"
        preferences[.ollama] = ollama
        preferences.placement = .pointer
        preferences.systemPrompt = "Custom"
        preferences.idleReset = .oneHour

        let reloaded = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(reloaded[.ollama].model == "qwen3")
        #expect(reloaded.activeProvider == .ollama)
        #expect(reloaded.placement == .pointer)
        #expect(reloaded.systemPrompt == "Custom")
        #expect(reloaded.idleReset == .oneHour)
    }

    @Test func idleResetDefaultsToHalfAnHourAndExpiresHiddenChats() {
        let preferences = Preferences(defaults: makeDefaults(), secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(preferences.idleReset == .thirtyMinutes)
        let hiddenAt = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(IdleReset.thirtyMinutes.hasExpired(since: hiddenAt, now: hiddenAt.addingTimeInterval(30 * 60)))
        #expect(!IdleReset.thirtyMinutes.hasExpired(since: hiddenAt, now: hiddenAt.addingTimeInterval(29 * 60)))
        #expect(!IdleReset.never.hasExpired(since: hiddenAt, now: hiddenAt.addingTimeInterval(24 * 60 * 60)))
        #expect(!IdleReset.fiveMinutes.hasExpired(since: nil, now: hiddenAt))
    }

    @Test func onDeviceModelStartsOnOnlyWhereItIsAvailable() {
        let withModel = Preferences(defaults: makeDefaults(), secrets: noSecrets, onDeviceModelAvailable: true)
        #expect(withModel.activeProvider == .apple)
        #expect(withModel.readyProviders == [.apple])

        var anthropic = withModel[.anthropic]
        anthropic.apiKey = "sk-test"
        withModel[.anthropic] = anthropic
        #expect(withModel.activeProvider == .anthropic, "a configured cloud provider outranks the on-device fallback")

        let withoutModel = Preferences(defaults: makeDefaults(), secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(withoutModel.activeProvider == nil)
        #expect(!withoutModel[.apple].isEnabled)
    }

    @Test func turningTheOnDeviceModelOffIsRemembered() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: true)
        var apple = preferences[.apple]
        apple.isEnabled = false
        preferences[.apple] = apple
        let reloaded = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: true)
        #expect(!reloaded[.apple].isEnabled)
        #expect(reloaded.activeProvider == nil)
    }

    @Test func disablingTheActiveProviderClearsIt() {
        let preferences = Preferences(defaults: makeDefaults(), secrets: noSecrets, onDeviceModelAvailable: false)
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
