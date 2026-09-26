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

    @Test func mcpChoicesPersist() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(preferences[.claudeCode].allowsMCP)
        #expect(preferences[.claudeCode].knownMCPServers.isEmpty)
        var claude = preferences[.claudeCode]
        claude.knownMCPServers = ["knowledge-rag", "vencord"]
        claude.disabledMCPServers = ["vencord"]
        preferences[.claudeCode] = claude
        var codex = preferences[.codex]
        codex.allowsMCP = false
        preferences[.codex] = codex

        let reloaded = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(reloaded[.claudeCode].knownMCPServers == ["knowledge-rag", "vencord"])
        #expect(reloaded[.claudeCode].disabledMCPServers == ["vencord"])
        #expect(reloaded[.claudeCode].allowedMCPServers == ["knowledge-rag"])
        #expect(!reloaded[.codex].allowsMCP)
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

    @Test func eachModeKeepsItsOwnProvider() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: true)
        #expect(preferences.mode == .llm)
        #expect(preferences.activeProvider == .apple)

        var claude = preferences[.claudeCode]
        claude.isEnabled = true
        preferences[.claudeCode] = claude
        #expect(preferences.mode == .llm, "turning an agent on leaves the mode alone")
        #expect(preferences.activeProvider == .apple)
        #expect(preferences.readyProviders(for: .agent) == [.claudeCode])
        #expect(preferences.readyProviders(for: .llm) == [.apple])

        preferences.mode = .agent
        #expect(preferences.activeProvider == .claudeCode)
        #expect(preferences.provider == .claudeCode)

        preferences.provider = .apple
        #expect(preferences.mode == .llm, "picking a provider of the other kind switches the mode")
        #expect(preferences.defaultProvider(for: .agent) == .claudeCode)

        preferences.setDefaultProvider(.claudeCode, for: .llm)
        #expect(preferences.defaultProvider(for: .llm) == .apple, "a provider only fits its own mode")

        let reloaded = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: true)
        #expect(reloaded.mode == .llm)
        #expect(reloaded.activeProvider == .apple)
        #expect(reloaded.defaultProvider(for: .agent) == .claudeCode)
        reloaded.mode = .agent
        #expect(Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: true).activeProvider == .claudeCode)
    }

    @Test func aModeWithNothingReadyHasNoProvider() {
        let preferences = Preferences(defaults: makeDefaults(), secrets: noSecrets, onDeviceModelAvailable: true)
        preferences.mode = .agent
        #expect(preferences.activeProvider == nil)
        #expect(preferences.defaultProvider(for: .llm) == .apple)
    }

    @Test func theSavedProviderStillPicksTheMode() {
        let defaults = makeDefaults()
        defaults.set("codex", forKey: "provider")
        defaults.set(true, forKey: "codex.enabled")
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: true)
        #expect(preferences.mode == .agent)
        #expect(preferences.activeProvider == .codex)
        #expect(preferences.defaultProvider(for: .llm) == .apple)
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
