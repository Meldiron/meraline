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

    @Test func listsOfYourOwnAnswersAreAddedEditedAndRemoved() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(preferences.decisionAnswers == "Yes / No")
        #expect(preferences.ownDecisionAnswers.isEmpty)
        preferences.addOwnAnswers(" Keep/Toss ")
        #expect(preferences.ownDecisionAnswers == ["Keep / Toss"], "written as the answers write themselves")
        #expect(preferences.decisionAnswers == "Keep / Toss")
        preferences.addOwnAnswers("Low < High")
        preferences.addOwnAnswers("Keep / Toss")
        #expect(preferences.ownDecisionAnswers == ["Keep / Toss", "Low < High"], "never twice")
        #expect(preferences.decisionAnswers == "Keep / Toss", "the one already there is used")
        preferences.addOwnAnswers("Keep /")
        #expect(preferences.ownDecisionAnswers.count == 2, "a text that reads as no answers isn't added")
        preferences.addOwnAnswers("No / Yes")
        #expect(preferences.ownDecisionAnswers.count == 2, "Yes and No are the model's own")
        #expect(preferences.decisionAnswers == "Yes / No")

        preferences.replaceOwnAnswers("Low < High", with: "Low < Medium < High")
        #expect(preferences.ownDecisionAnswers == ["Keep / Toss", "Low < Medium < High"], "an edit keeps its place")
        #expect(preferences.decisionAnswers == "Low < Medium < High")
        preferences.replaceOwnAnswers("Low < Medium < High", with: "Keep / Toss")
        #expect(preferences.ownDecisionAnswers == ["Keep / Toss"], "an edit that matches another list gives way to it")
        #expect(preferences.decisionAnswers == "Keep / Toss")

        preferences.addOwnAnswers("Low < High")
        preferences.decisionAnswers = "Keep / Toss"
        preferences.removeOwnAnswers("Low < High")
        #expect(preferences.ownDecisionAnswers == ["Keep / Toss"])
        #expect(preferences.decisionAnswers == "Keep / Toss", "removing another list leaves the one in use")
        preferences.removeOwnAnswers("Keep / Toss")
        #expect(preferences.ownDecisionAnswers.isEmpty)
        #expect(preferences.decisionAnswers == "Yes / No", "Yes / No takes the place of the list in use")

        preferences.decisionAnswers = "Billing / Sales"
        #expect(preferences.ownDecisionAnswers == ["Billing / Sales"], "answers in use are always among your own")
        preferences.addOwnAnswers("Low < High")
        let again = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(again.ownDecisionAnswers == ["Billing / Sales", "Low < High"])
        #expect(again.decisionAnswers == "Low < High")
    }

    @Test func answersOfOlderVersionsBecomeListsOfYourOwn() {
        // Settings' field wrote the answers in use, and the panel kept one list apart.
        let older = makeDefaults()
        older.set("Low<High", forKey: "decisions.answers")
        older.set("Keep / Toss", forKey: "decisions.ownAnswers")
        let preferences = Preferences(defaults: older, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(preferences.ownDecisionAnswers == ["Keep / Toss", "Low < High"])
        #expect(preferences.decisionAnswers == "Low < High")
        // A text that read as no answers picked Yes or No, and still does.
        let unread = makeDefaults()
        unread.set("Keep /", forKey: "decisions.answers")
        let yesNo = Preferences(defaults: unread, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(yesNo.decisionAnswers == "Yes / No")
        #expect(yesNo.ownDecisionAnswers.isEmpty)
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
        preferences[prompt: .chat(.llm)] = "Custom"

        let reloaded = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(reloaded[.ollama].model == "qwen3")
        #expect(reloaded.activeProvider == .ollama)
        #expect(reloaded.placement == .pointer)
        #expect(reloaded[prompt: .chat(.llm)] == "Custom")
    }

    @Test func eachPromptIsKeptOnlyWhileChanged() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets)
        for prompt in SystemPrompt.allCases {
            #expect(preferences[prompt: prompt] == prompt.standard)
            #expect(!preferences.isChanged(prompt))
        }
        #expect(Set(SystemPrompt.allCases.map(\.key)).count == SystemPrompt.allCases.count, "every prompt has a key of its own")
        #expect(SystemPrompt.llm != SystemPrompt.agent)

        preferences[prompt: .chat(.agent)] = "Agents only."
        preferences[prompt: .game(.rhymeDuel)] = "Rhyme in Czech."
        #expect(preferences[prompt: .chat(.llm)] == SystemPrompt.llm, "changing the agents' prompt leaves the LLMs' alone")
        #expect(preferences.isChanged(.game(.rhymeDuel)))
        #expect(!preferences.isChanged(.game(.categories)))

        let reloaded = Preferences(defaults: defaults, secrets: noSecrets)
        #expect(reloaded[prompt: .chat(.agent)] == "Agents only.")
        #expect(reloaded[prompt: .game(.rhymeDuel)] == "Rhyme in Czech.")

        reloaded[prompt: .game(.rhymeDuel)] = RhymeDuel.systemPrompt
        #expect(!reloaded.isChanged(.game(.rhymeDuel)))
        #expect(defaults.object(forKey: SystemPrompt.game(.rhymeDuel).key) == nil, "a prompt set back to its default follows later defaults")
    }

    @Test func theLanguageIsEnglishUntilChangedAndFollowsEveryPrompt() throws {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults, secrets: noSecrets)
        #expect(preferences.language == .english)
        #expect(preferences.instructions(for: .chat(.llm)) == "\(SystemPrompt.llm)\n\nWrite your answers in English, unless the user asks for another language, as for a translation.")
        #expect(preferences.instructions(for: .game(.rhymeDuel)) == RhymeDuel.systemPrompt, "the games are written in English")
        #expect(preferences.instructions(for: .toolReason) == ToolReason.systemPrompt)

        preferences.language = .czech
        preferences[prompt: .chat(.agent)] = "Agents only."
        #expect(preferences.instructions(for: .chat(.agent)) == "Agents only.\n\nWrite your answers in Czech, unless the user asks for another language, as for a translation.", "a changed prompt keeps the language")
        let game = preferences.instructions(for: .game(.categories))
        #expect(game.hasPrefix("\(Categories.systemPrompt)\n\nPlay the game in Czech: "))
        #expect(game.contains("“OK: ”") && game.contains("“ | ”"), "the markers the game reads stay as they are")
        #expect(preferences.instructions(for: .toolReason).hasSuffix("\n\nWrite the sentence in Czech."))
        #expect(preferences[prompt: .chat(.agent)] == "Agents only.", "the line is added, never saved into the prompt")

        let reloaded = Preferences(defaults: defaults, secrets: noSecrets)
        #expect(reloaded.language == .czech)
    }

    @Test func theLanguagesHaveTheirOwnNames() {
        #expect(AnswerLanguage.allCases.prefix(3) == [.english, .czech, .slovak])
        #expect(AnswerLanguage.czech.title == "Czech (Čeština)")
        #expect(AnswerLanguage.slovak.title == "Slovak (Slovenčina)")
        #expect(AnswerLanguage.english.title == "English")
        #expect(AnswerLanguage.chinese.name == "Simplified Chinese")
        let rest = AnswerLanguage.allCases.dropFirst(3).map(\.name)
        #expect(rest == rest.sorted(), "after English, Czech, and Slovak, by name")
        #expect(Set(AnswerLanguage.allCases.map(\.endonym)).count == AnswerLanguage.allCases.count)
    }

    @Test func theOnePromptOfOlderVersionsCarriesOverToBothModes() {
        let changed = makeDefaults()
        changed.set("Answer in Czech.", forKey: SystemPrompt.legacyKey)
        let preferences = Preferences(defaults: changed, secrets: noSecrets)
        #expect(preferences[prompt: .chat(.llm)] == "Answer in Czech.")
        #expect(preferences[prompt: .chat(.agent)] == "Answer in Czech.")
        #expect(changed.object(forKey: SystemPrompt.legacyKey) == nil)

        preferences[prompt: .chat(.agent)] = SystemPrompt.agent
        let reloaded = Preferences(defaults: changed, secrets: noSecrets)
        #expect(reloaded[prompt: .chat(.agent)] == SystemPrompt.agent, "restoring the agents' default sticks")
        #expect(reloaded[prompt: .chat(.llm)] == "Answer in Czech.")

        let untouched = makeDefaults()
        untouched.set(SystemPrompt.llm, forKey: SystemPrompt.legacyKey)
        let fresh = Preferences(defaults: untouched, secrets: noSecrets)
        #expect(!fresh.isChanged(.chat(.llm)))
        #expect(!fresh.isChanged(.chat(.agent)), "the old default isn't a change, so agents get their own default")
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
