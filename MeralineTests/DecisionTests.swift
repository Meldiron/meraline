import AppKit
import Foundation
import Testing
@testable import Meraline

/// Decision mode: the answers a question names, the request a decision model gets (TypeSafe's Jev directly, any
/// through OpenRouter, or Nimble or Tev1 through Ollama on this Mac) and the reply it sends, and what the chat does with a decision. Context is optional (the row only suggests it), it keeps any context for
/// follow-ups, writes the answer in words, offers no rewrite, and plays no game against Jev.
@MainActor
struct DecisionTests {
    private typealias Support = GameTestSupport

    private static func throwaway() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func preferences(_ defaults: UserDefaults) -> Preferences {
        Preferences(defaults: defaults, secrets: SecretStore(read: { _ in "" }, write: { _, _ in }), onDeviceModelAvailable: false)
    }

    /// A session in Decision mode with TypeSafe ready, and an LLM too.
    private static func decisionSession(_ model: ScriptedModel) -> (session: ChatSession, preferences: Preferences) {
        let preferences = Support.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        preferences.mode = .decision
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        return (session, preferences)
    }

    private static let yes = Decision(options: [.init(label: "Yes", probability: 0.91), .init(label: "No", probability: 0.09)], isYesNo: true, confidence: 0.82)
    private static let no = Decision(options: [.init(label: "Yes", probability: 0.2), .init(label: "No", probability: 0.8)], isYesNo: true, confidence: 0.6)

    // MARK: The mode

    @Test func typeSafeIsADecisionModelOfItsOwnMode() {
        #expect(Provider.typeSafe.kind == .decision)
        #expect(ProviderKind.decision.providers == [.typeSafe, .openRouterDecision, .ollamaDecision])
        #expect(Provider.typeSafe.keyPolicy == .required)
        #expect(Provider.typeSafe.defaultModel == "jev-latest")
        #expect(!SystemPrompt.allCases.contains(.chat(.decision)), "Jev takes no prompt, so Settings › Prompt has none for it")
        #expect(ProviderKind.prompted == [.llm, .agent])
        #expect(PriceTable(prices: [:], fetched: .now).price(for: .typeSafe, model: "jev-latest") == .jev, "TypeSafe's list price, which OpenRouter doesn't carry")
        #expect(abs(ModelPrice.jev.cost(of: .init(input: 1_000_000)) - 0.042) < 1e-12)
        #expect(PromptPreset.exists("scale.3d"))
        #expect(PromptPreset.exists(Provider.typeSafe.symbol))
    }

    // MARK: Answers

    @Test func openRouterServesDecisionModelsOnItsLLMsKey() throws {
        let provider = Provider.openRouterDecision
        #expect(provider.kind == .decision)
        #expect(provider.name == "OpenRouter")
        #expect(provider.keyPolicy == .required)
        #expect(provider.sharesKey == .openRouter && provider.keyAccount == Provider.openRouter.rawValue)
        #expect(Provider.typeSafe.sharesKey == nil && Provider.typeSafe.keyAccount == "typeSafe")
        #expect(Provider.allCases.filter { $0.sharesKey != nil } == [provider], "only OpenRouter's two entries are one account")
        #expect(provider.defaultModel == "typesafe/jev-1.13")
        #expect(provider.suggestedModels == Provider.openRouterDecisionModels)
        #expect(provider.suggestedModels.first == provider.defaultModel)
        #expect(provider.suggestedModels.allSatisfy { $0.contains("/") }, "OpenRouter's ids, lab/model")
        #expect(!provider.suggestedModels.contains { $0.hasPrefix("respan/") }, "Span-01 reads only a conversation transcript")
        #expect(PromptPreset.exists(provider.symbol))

        // The request goes to OpenRouter's System One endpoint, with the model id as OpenRouter lists it.
        let settings = ProviderSettings(model: "liquid/d1", baseURL: provider.defaultBaseURL, apiKey: "sk-or-test", isEnabled: true)
        #expect(settings.isReady(for: provider))
        let request = DecisionRequest(state: [try #require(SelectedText("Production is down.", appName: "Mail"))], question: "Is this urgent?", answers: .yesNo)
        let urlRequest = try DecisionClient.urlRequest(request, settings: settings, provider: provider)
        #expect(urlRequest.url?.absoluteString == "https://openrouter.ai/api/v1/systemone")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
        let sentBody = try #require(urlRequest.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(body["model"] as? String == "liquid/d1")

        // Its price: OpenRouter's when the list has the model, else Jev's. OpenRouter says what each answer cost anyway.
        let d1 = ModelPrice(prompt: 0.04 / 1_000_000, completion: 0)
        let table = PriceTable(prices: ["liquid/d1": d1], fetched: .now)
        #expect(table.price(for: provider, model: "liquid/d1") == d1)
        #expect(table.price(for: provider, model: "inception/mercury-decide:free") == .jev)
        #expect(table.price(for: provider, model: "typesafe/jev-1.13") == .jev)
    }

    @Test func ollamaDecidesOnThisMac() throws {
        let provider = Provider.ollamaDecision
        #expect(provider.kind == .decision)
        #expect(provider.name == "Ollama" && provider.symbol == Provider.ollama.symbol && provider.tint == Provider.ollama.tint)
        #expect(provider.keyPolicy == .none && provider.sharesKey == nil && provider.keyPortal == Provider.ollama.keyPortal)
        #expect(provider.runsOnThisMac && Provider.ollama.runsOnThisMac && Provider.apple.runsOnThisMac)
        #expect(!Provider.typeSafe.runsOnThisMac && !Provider.openRouterDecision.runsOnThisMac && !Provider.custom.runsOnThisMac)
        #expect(provider.defaultModel == "nimble")
        #expect(provider.suggestedModels == ["nimble", "tev1", "tev1:0.8b"] && provider.suggestedModels.first == provider.defaultModel)
        #expect(provider.defaultBaseURL == "http://127.0.0.1:11434/v1")
        #expect(Provider.allCases.last == .apple, "the on-device model still sorts last")
        #expect(PromptPreset.exists(provider.symbol))

        // Off until Settings turns it on, like Ollama under LLMs, and then ready with a model and no key.
        var settings = ProviderSettings(model: "nimble", baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: false)
        #expect(!settings.isReady(for: provider))
        settings.isEnabled = true
        #expect(settings.isReady(for: provider))
        #expect(!ProviderSettings(model: "", baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: true).isReady(for: provider), "a model is needed, as under LLMs")

        // The request goes to Ollama's System One endpoint on this Mac, with no key and time for the model to load.
        let mail = try #require(SelectedText("Production is down.", appName: "Mail"))
        let request = DecisionRequest(state: [mail], question: "Is this urgent?", answers: .yesNo)
        settings.model = ""
        let urlRequest = try DecisionClient.urlRequest(request, settings: settings, provider: provider)
        #expect(urlRequest.url?.absoluteString == "http://127.0.0.1:11434/v1/systemone")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(urlRequest.timeoutInterval == 120)
        let sentBody = try #require(urlRequest.httpBody)
        let sent = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(sent["model"] as? String == "nimble", "the provider's default model when none is set")

        // Free, whatever the price list says, in the ledger too.
        #expect(PriceTable(prices: [:], fetched: .now).price(for: provider, model: "nimble") == .free)
        #expect(UsageLedger(file: nil).price(for: provider, model: "tev1:0.8b") == .free)

        // Its replies, as tev1 answered on 2026-10-02: Jev's shapes, with a confidence and a legend on a set and levels.
        let yes = try DecisionClient.decode(Data("""
        {"model":"tev1:0.8b","answers":{"decision":{"type":"noul","noul":0.9141597037372717}},"usage":{"input_tokens":126,"output_tokens":1}}
        """.utf8), for: .yesNo, from: provider)
        #expect(yes.decision.chosen.label == "Yes" && yes.usage == TokenUsage(input: 126, output: 1, model: "tev1:0.8b"))
        let team = try DecisionClient.decode(Data("""
        {"model":"tev1:0.8b","answers":{"decision":{"type":"choice","choice":"Billing","probabilities":{"Billing":0.9609486554519427,"Technical":0.036720162678455744,"Sales":0.0023311818696014554},"confidence":0.8418476852320123}},"usage":{"input_tokens":138,"output_tokens":1}}
        """.utf8), for: DecisionAnswers(options: ["Billing", "Technical", "Sales"], isOrdered: false), from: provider)
        #expect(team.decision.chosen.label == "Billing" && abs(team.decision.confidence - 0.8418476852320123) < 1e-12)
        let level = try DecisionClient.decode(Data("""
        {"model":"tev1:0.8b","answers":{"decision":{"type":"score","score":1.4048956374281032,"legend":{"0":"Low","1":"Medium","2":"High"},"probabilities":{"0":0.15461484198520098,"1":0.2858746786014951,"2":0.559510479413304},"confidence":0.11568948716450045}},"usage":{"input_tokens":134,"output_tokens":1}}
        """.utf8), for: DecisionAnswers(options: ["Low", "Medium", "High"], isOrdered: true), from: provider)
        #expect(level.decision.chosen.label == "High" && level.decision.isOrdered)
        let score = try #require(level.decision.score)
        #expect(abs(score - 1.4048956374281032) < 1e-12)
        #expect(StreamDecoder.errorMessage(from: Data(#"{"error":"model \"nimble\" not found, try pulling it first"}"#.utf8)) == "model \"nimble\" not found, try pulling it first", "Ollama's error reads as it is")

        // Turned on in Settings, it is the decision model when it is the only one ready; Ollama under LLMs is its own switch.
        let preferences = Self.preferences(Self.throwaway())
        #expect(preferences.readyProviders(for: .decision).isEmpty)
        var ollama = preferences[provider]
        ollama.isEnabled = true
        preferences[provider] = ollama
        #expect(preferences.readyProviders(for: .decision) == [provider] && preferences.defaultProvider(for: .decision) == provider)
        #expect(!preferences[.ollama].isEnabled && preferences.readyProviders(for: .llm).isEmpty)
    }

    @Test func ollamaGetsEightQuestionsARequestAboutOnlyTheirItems() throws {
        // Ollama reads every question of a request in each prompt, and a prompt takes at most 2,050 tokens.
        #expect(Provider.ollamaDecision.questionsPerRequest == 8 && Provider.ollamaDecision.trimsDecisionState)
        #expect(Provider.typeSafe.questionsPerRequest == DecisionScope.batchSize && !Provider.typeSafe.trimsDecisionState)
        #expect(Provider.openRouterDecision.questionsPerRequest == DecisionScope.batchSize && !Provider.openRouterDecision.trimsDecisionState)

        let lines = (1...20).map { "Task \($0)" }
        let notes = try #require(SelectedText(lines.joined(separator: "\n"), appName: "Notes"))
        let request = DecisionRequest(state: [notes], question: "Is this urgent?", answers: .yesNo, scope: .lines, items: lines)
        let body = request.body(model: "tev1", itemsFrom: 8, count: 8, trimmed: true)
        let state = try #require(body["state"] as? [String: Any])
        #expect(state["items"] as? [String] == Array(lines[8..<16]), "only the batch's items")
        #expect(state["text"] as? String == notes.text && state["from"] as? String == "Notes", "and the text, since it is short")
        let questions = try #require(body["questions"] as? [String: [String: Any]])
        #expect(questions.count == 8 && questions["item_7"] == nil && questions["item_16"] == nil)
        #expect(questions["item_8"]?["instructions"] as? [String: String] == ["question": "Is this urgent?", "about": "items[0]", "item": "Task 9"], "named by its place among all the items, about its place in the batch")
        #expect(questions["item_15"]?["instructions"] as? [String: String] == ["question": "Is this urgent?", "about": "items[7]", "item": "Task 16"])
        #expect(JSONSerialization.isValidJSONObject(body))
        let untrimmed = request.body(model: "tev1", itemsFrom: 8, count: 8)
        #expect((untrimmed["state"] as? [String: Any])?["items"] as? [String] == lines, "Jev gets them all")
        #expect((untrimmed["questions"] as? [String: [String: Any]])?["item_8"]?["instructions"] as? [String: String] == ["question": "Is this urgent?", "about": "items[8]", "item": "Task 9"])

        // A long text stays out of a trimmed request, so the items alone are the state.
        let long = (1...400).map { "Task \($0) needs doing" }
        let essay = try #require(SelectedText(long.joined(separator: "\n"), appName: "Notes"))
        let longRequest = DecisionRequest(state: [essay], question: "Is this urgent?", answers: .yesNo, scope: .lines, items: long)
        #expect(!longRequest.textsFitTrimmed && request.textsFitTrimmed)
        let longState = try #require(longRequest.body(model: "tev1", itemsFrom: 392, count: 8, trimmed: true)["state"] as? [String: Any])
        #expect(longState.keys.sorted() == ["items"] && longState["items"] as? [String] == Array(long[392...]))

        // The reply reads as any batch does, as tev1 answered on 2026-10-02.
        let batch = try DecisionClient.decodeBatch(Data("""
        {"model":"tev1:0.8b","answers":{"item_8":{"type":"noul","noul":0.7657548779340712},"item_9":{"type":"noul","noul":0.25}},"usage":{"input_tokens":906,"output_tokens":4}}
        """.utf8), for: request, from: 8, count: 2, provider: .ollamaDecision)
        #expect(batch.items.map(\.id) == [8, 9] && batch.items.map(\.text) == ["Task 9", "Task 10"])
        #expect(batch.items.map { $0.decision.chosen.label } == ["Yes", "No"])
    }

    @Test func openRoutersKeyIsPastedOnceForLLMsAndDecisions() {
        final class Vault: @unchecked Sendable { var items: [String: String] = [:] }
        let vault = Vault()
        let secrets = SecretStore(read: { vault.items[$0] ?? "" }, write: { vault.items[$0] = $1 })
        let defaults = Self.throwaway()
        let preferences = Preferences(defaults: defaults, secrets: secrets, onDeviceModelAvailable: false)
        #expect(preferences.readyProviders(for: .decision).isEmpty)

        var llm = preferences[.openRouter]
        llm.apiKey = " sk-or-test "
        preferences[.openRouter] = llm
        #expect(vault.items == ["openRouter": "sk-or-test"], "one Keychain item, trimmed")
        #expect(preferences[.openRouterDecision].apiKey == " sk-or-test ", "the key pasted under LLMs serves decisions")
        #expect(preferences.readyProviders(for: .decision) == [.openRouterDecision], "ready at once, on its default model")
        #expect(preferences.defaultProvider(for: .decision) == .openRouterDecision)

        var decision = preferences[.openRouterDecision]
        decision.apiKey = "sk-or-new"
        preferences[.openRouterDecision] = decision
        #expect(vault.items == ["openRouter": "sk-or-new"], "and the other way round")
        #expect(preferences[.openRouter].apiKey == "sk-or-new")

        let reloaded = Preferences(defaults: defaults, secrets: secrets, onDeviceModelAvailable: false)
        #expect(reloaded[.openRouter].apiKey == "sk-or-new" && reloaded[.openRouterDecision].apiKey == "sk-or-new")
        #expect(reloaded.defaultProvider(for: .decision) == .openRouterDecision)

        decision.apiKey = ""
        reloaded[.openRouterDecision] = decision
        #expect(vault.items == ["openRouter": ""] && reloaded[.openRouter].apiKey.isEmpty, "taking it out takes it out of both")
        #expect(reloaded.defaultProvider(for: .decision) == nil && reloaded.defaultProvider(for: .llm) == nil)
    }

    @Test func openRoutersReplyReadsWithWhatItCost() throws {
        // As OpenRouter answered on 2026-10-02, with fields TypeSafe's reply doesn't have.
        let reply = try DecisionClient.decode(Data("""
        {"model":"typesafe/jev-1.13-20260917","answers":{"decision":{"type":"noul","noul":0.88}},"usage":{"input_tokens":289,"output_tokens":20,"cost":0.000012138},"id":"gen-dec-1790928720-YgHwYgOMvVoROVtWem15","provider":"TypeSafe"}
        """.utf8), for: .yesNo, from: .openRouterDecision)
        #expect(reply.decision.chosen.label == "Yes")
        #expect(reply.usage.input == 289 && reply.usage.output == 20 && reply.usage.model == "typesafe/jev-1.13-20260917")
        let cost = try #require(reply.usage.cost)
        #expect(abs(cost - 0.000012138) < 1e-12, "what OpenRouter charged, for the ledger")

        let level = try DecisionClient.decode(Data("""
        {"model":"liquid/d1-20260930","answers":{"decision":{"type":"score","score":1.6255723345475035,"legend":{"0":"Low","1":"Medium","2":"High"},"probabilities":{"0":0.07370308720822435,"1":0.22702149103604768,"2":0.6992754217557279},"confidence":0.5489131326335919}},"usage":{"input_tokens":64,"output_tokens":0,"cost":0.00000256},"id":"gen-dec-1790928728-SQ4hu1BFscqNtjEzzaxY","provider":"Liquid"}
        """.utf8), for: DecisionAnswers(options: ["Low", "Medium", "High"], isOrdered: true), from: .openRouterDecision)
        #expect(level.decision.chosen.label == "High" && level.decision.isOrdered)
        let score = try #require(level.decision.score)
        #expect(abs(score - 1.6255723345475035) < 1e-12)

        let request = DecisionRequest(state: [try #require(SelectedText.typed("Buy milk"))], question: "Is this a verb?", answers: .yesNo, scope: .words, items: ["Buy", "milk"])
        let batch = try DecisionClient.decodeBatch(Data("""
        {"model":"typesafe/jev-1.13-20260917","answers":{"item_0":{"type":"noul","noul":0.97},"item_1":{"type":"noul","noul":0.25}},"usage":{"input_tokens":411,"output_tokens":58,"cost":0.000017262},"id":"gen-dec-1790928721-GKTaYSdbaMQTCsM64Wcc","provider":"TypeSafe"}
        """.utf8), for: request, from: 0, count: 100, provider: .openRouterDecision)
        #expect(batch.items.map { $0.decision.chosen.label } == ["Yes", "No"])
        let batchCost = try #require(batch.usage.cost)
        #expect(abs(batchCost - 0.000017262) < 1e-12)

        #expect(throws: LLMError.provider("OpenRouter answered with a “poem” question, which Meraline doesn’t know.")) {
            try DecisionClient.decode(Data(#"{"answers": {"decision": {"type": "poem"}}}"#.utf8), for: .yesNo, from: .openRouterDecision)
        }
    }

    @Test func answersComeAfterTheQuestionOrFromSettings() {
        let plain = DecisionAnswers.split("Is this urgent?", fallback: .yesNo)
        #expect(plain.question == "Is this urgent?")
        #expect(plain.answers == .yesNo)
        #expect(plain.answers.kind == .yesNo)
        let named = DecisionAnswers.split(" Which team should handle this? Billing / Technical / Sales ", fallback: .yesNo)
        #expect(named.question == "Which team should handle this?")
        #expect(named.answers.options == ["Billing", "Technical", "Sales"])
        #expect(named.answers.kind == .choice)
        #expect(named.answers.text == "Billing / Technical / Sales")
        let ordered = DecisionAnswers.split("How urgent is this? Low < Medium < High", fallback: .yesNo)
        #expect(ordered.answers == DecisionAnswers(options: ["Low", "Medium", "High"], isOrdered: true))
        #expect(ordered.answers.kind == .score)
        #expect(ordered.answers.text == "Low < Medium < High")
        #expect(DecisionAnswers.split("Pick one: Keep / Toss", fallback: .yesNo).answers.options == ["Keep", "Toss"], "a colon does too")
        #expect(DecisionAnswers.split("Is this TCP/IP?", fallback: .yesNo).question == "Is this TCP/IP?", "a slash before the question mark is part of the question")
        #expect(DecisionAnswers.split("Is the ratio 3/4 right?", fallback: .yesNo).answers == .yesNo)
        #expect(DecisionAnswers.split("Is it urgent", fallback: DecisionAnswers(options: ["Keep", "Toss"], isOrdered: false)).answers.options == ["Keep", "Toss"], "Settings' answers when the question names none")
        #expect(DecisionAnswers.split("Pick one: No / Yes", fallback: .yesNo).answers.isYesNo, "Yes and No in any order are Jev's yes/no question")
        #expect(DecisionAnswers.split("Pick one: yes / no", fallback: .yesNo).answers.kind == .yesNo)
        #expect(DecisionAnswers.parse("Yes / No") == .yesNo)
        #expect(DecisionAnswers.parse("Yes") == nil, "one answer is no choice")
        #expect(DecisionAnswers.parse("Yes / Yes") == nil, "nor two alike")
        #expect(DecisionAnswers.parse("Yes / ") == nil)
        #expect(DecisionAnswers.parse(String(repeating: "a", count: 41) + " / b") == nil, "an answer is a word or a few, not a sentence")
        #expect(DecisionAnswers.parse((1...11).map(String.init).joined(separator: " < "))?.kind == .choice, "more levels than Jev takes in order go as a set")
        #expect(DecisionAnswers.parse((1...10).map(String.init).joined(separator: " < "))?.kind == .score)
    }

    // MARK: The request and the reply

    @Test func theRequestCarriesTheTextsTheQuestionAndTheAnswers() throws {
        let mail = try #require(SelectedText("Please send the report by noon.", appName: "Mail"))
        let request = DecisionRequest(state: [mail], question: "Is this urgent?", answers: .yesNo)
        let body = request.body(model: "jev-latest")
        #expect(body["model"] as? String == "jev-latest")
        let state = try #require(body["state"] as? [String: Any])
        #expect(state["text"] as? String == "Please send the report by noon.")
        #expect(state["from"] as? String == "Mail")
        let questions = try #require(body["questions"] as? [String: [String: Any]])
        #expect(questions["decision"]?["type"] as? String == "noul")
        #expect(questions["decision"]?["instructions"] as? String == "Is this urgent?")
        #expect(questions["decision"]?["criteria"] == nil)

        let team = DecisionRequest(
            state: [mail, try #require(SelectedText.typed("Ticket 42"))],
            question: "Which team?",
            answers: DecisionAnswers(options: ["Billing", "Sales"], isOrdered: false)
        )
        let teamBody = team.body(model: "jev-1.13.0")
        let texts = try #require((teamBody["state"] as? [String: Any])?["texts"] as? [[String: Any]])
        #expect(texts.map { $0["text"] as? String } == ["Please send the report by noon.", "Ticket 42"])
        #expect(texts[1]["from"] == nil, "text written in the window comes from no app")
        let teamQuestion = try #require((teamBody["questions"] as? [String: [String: Any]])?["decision"])
        #expect(teamQuestion["type"] as? String == "choice")
        let criteria = try #require(teamQuestion["criteria"] as? [String: Any])
        #expect(Set(criteria.keys) == ["Billing", "Sales"])
        #expect(criteria.values.allSatisfy { $0 is NSNull }, "no descriptions")
        #expect(JSONSerialization.isValidJSONObject(teamBody))

        let levels = DecisionRequest(state: [mail], question: "How urgent?", answers: DecisionAnswers(options: ["Low", "High"], isOrdered: true))
        let levelsQuestion = try #require((levels.body(model: "jev-latest")["questions"] as? [String: [String: Any]])?["decision"])
        #expect(levelsQuestion["type"] as? String == "score")
        #expect(levelsQuestion["criteria"] as? [String] == ["Low", "High"])

        let settings = ProviderSettings(model: "", baseURL: "https://api.typesafe.ai/v1", apiKey: "sk-test", isEnabled: true)
        let urlRequest = try DecisionClient.urlRequest(request, settings: settings)
        #expect(urlRequest.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let sentBody = try #require(urlRequest.httpBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(sent["model"] as? String == "jev-latest", "the provider's default model when none is set")
        #expect(throws: LLMError.missingKey(.typeSafe)) {
            try DecisionClient.urlRequest(request, settings: ProviderSettings(model: "", baseURL: "https://api.typesafe.ai/v1", apiKey: "", isEnabled: true))
        }
        #expect(throws: (any Error).self) {
            try DecisionClient.urlRequest(DecisionRequest(state: [], question: "Is it?", answers: .yesNo), settings: settings)
        }
        #expect(throws: LLMError.invalidBaseURL("nowhere")) {
            try DecisionClient.urlRequest(request, settings: ProviderSettings(model: "", baseURL: "nowhere", apiKey: "sk-test", isEnabled: true))
        }
    }

    @Test func aReplyReadsIntoADecision() throws {
        let yes = Data("""
        {"model": "jev-1.13.0", "answers": {"decision": {"type": "noul", "noul": 0.93}}, "usage": {"input_tokens": 360, "output_tokens": 39}}
        """.utf8)
        let reply = try DecisionClient.decode(yes, for: .yesNo)
        #expect(reply.decision.isYesNo)
        #expect(reply.decision.chosen.label == "Yes")
        #expect(abs(reply.decision.confidence - 0.86) < 1e-9, "twice the probability of yes less one")
        #expect(reply.decision.options.map(\.label) == ["Yes", "No"])
        #expect(abs(reply.decision.options[1].probability - 0.07) < 1e-9)
        #expect(reply.usage == TokenUsage(input: 360, output: 39, model: "jev-1.13.0"))
        #expect(reply.decision.verdict(unsureBelow: 0.5) == .yes)
        #expect(reply.decision.summary(unsureBelow: 0.5) == "Yes (86% confident)")

        let no = try DecisionClient.decode(Data(#"{"answers": {"decision": {"type": "noul", "noul": 0.2}}}"#.utf8), for: DecisionAnswers(options: ["No", "Yes"], isOrdered: false))
        #expect(no.decision.chosen.label == "No")
        #expect(no.decision.verdict(unsureBelow: 0.5) == .no)
        #expect(no.decision.summary(unsureBelow: 0.7) == "Not sure, leaning No (60% confident)")
        #expect(no.decision.verdict(unsureBelow: 0.7) == .unsure)
        #expect(no.usage == TokenUsage())

        let team = try DecisionClient.decode(Data("""
        {"model": "jev-1.13.0", "answers": {"decision": {"type": "choice", "choice": "technical", "confidence": 0.78, "probabilities": {"technical": 0.85, "sales": 0.0, "billing": 0.15}}}}
        """.utf8), for: DecisionAnswers(options: ["billing", "technical", "sales"], isOrdered: false))
        #expect(team.decision.options.map(\.probability) == [0.15, 0.85, 0], "in the answers' order")
        #expect(team.decision.chosen.label == "technical")
        #expect(team.decision.confidence == 0.78)
        #expect(team.decision.verdict(unsureBelow: 0.5) == .chosen, "your own answers get no color")
        #expect(team.decision.summary(unsureBelow: 0.5) == "technical (78% confident)")

        let level = try DecisionClient.decode(Data("""
        {"answers": {"decision": {"type": "score", "score": 1.4, "confidence": 0.6, "legend": {"0": "Low", "1": "Medium", "2": "High"}, "probabilities": {"0": 0.1, "1": 0.4, "2": 0.5}}}}
        """.utf8), for: DecisionAnswers(options: ["Low", "Medium", "High"], isOrdered: true))
        #expect(level.decision.isOrdered)
        #expect(level.decision.score == 1.4)
        #expect(level.decision.chosen.label == "High")
        #expect(level.decision.options.map(\.probability) == [0.1, 0.4, 0.5])

        let even = try DecisionClient.decode(Data(#"{"answers": {"decision": {"type": "choice", "choice": "a", "probabilities": {"a": 0.5, "b": 0.5}}}}"#.utf8), for: DecisionAnswers(options: ["a", "b"], isOrdered: false))
        #expect(even.decision.confidence == 0, "worked out from an even spread when the reply carries none")
        #expect(even.decision.chosen.label == "a", "the first among equals")
        #expect(throws: (any Error).self) { try DecisionClient.decode(Data(#"{"answers": {}}"#.utf8), for: .yesNo) }
        #expect(throws: (any Error).self) { try DecisionClient.decode(Data(#"{"answers": {"decision": {"type": "poem"}}}"#.utf8), for: .yesNo) }
        #expect(abs(Decision.confidence(over: [0.85, 0.15, 0]) - 0.775) < 1e-9)
        #expect(Decision.confidence(over: [1]) == 0)
        #expect(Decision.percent(0.856) == "86%")
        #expect(Decision.percent(1.7) == "100%")
    }

    // MARK: The chat

    @Test func aDecisionKeepsItsContextForFollowUps() async throws {
        let model = ScriptedModel(decisions: [Self.yes, Self.no])
        let (session, _) = Self.decisionSession(model)
        session.draft = "Is this urgent?"
        #expect(session.isDeciding)
        #expect(session.canSend, "context is optional, so the question alone can be asked")
        #expect(session.needsDecisionState, "the row still suggests adding context")
        session.writeState()
        #expect(!session.needsDecisionState, "the card to write it in stands in the row's place")
        session.removeTypedState()
        #expect(session.needsDecisionState, "and the row is back once the card goes")
        let mail = try #require(SelectedText("Please send the report by noon.", appName: "Mail"))
        session.bring(mail)
        #expect(session.canSend)
        #expect(!session.needsDecisionState)
        session.send()
        await Support.settle(session)
        let request = try #require(model.requests.last?.decision)
        #expect(request.state.map(\.text) == [mail.text])
        #expect(request.question == "Is this urgent?")
        #expect(request.answers == .yesNo)
        #expect(model.requests.last?.systemPrompt == "", "Jev takes no prompt")
        #expect(session.turns.last?.decision == Self.yes)
        #expect(session.turns.last?.answer == "Yes (82% confident)")
        #expect(session.lastAnswer == "Yes (82% confident)")
        #expect(!session.canRewrite, "a decision isn't text to rewrite")
        #expect(session.canAskAgain)
        #expect(session.followUps.isEmpty && !session.isSuggestingFollowUps, "no follow-ups are suggested for a word and a number")
        #expect(session.usage.summary(.day).decisions == 1)
        #expect(session.usage.summary(.day).unsureDecisions == 0)
        #expect(session.usage.summary(.day).answers == 1)

        // A follow-up asks about the same text, which the chat keeps.
        session.draft = "Should I reply today? Yes / No"
        #expect(session.canSend, "the chat has text to decide about")
        session.send()
        await Support.settle(session)
        let followUp = try #require(model.requests.last?.decision)
        #expect(followUp.state.map(\.text) == [mail.text])
        #expect(followUp.question == "Should I reply today?")
        #expect(session.turns.count == 2)
        #expect(session.turns.last?.selections.isEmpty == true, "the text is quoted once, on the question that brought it")
        #expect(session.turns.last?.answer == "No (60% confident)")
        #expect(session.turns.last?.changes == nil)
        #expect(ChatSession.markdown(for: session.turns)?.contains("**Assistant**\n\nYes (82% confident)") == true)
    }

    @Test func aDecisionCanBeAskedWithoutAnyContext() async throws {
        let model = ScriptedModel(decisions: [Self.yes])
        let (session, _) = Self.decisionSession(model)
        session.draft = "Is 17 a prime number?"
        #expect(session.canSend, "context is optional")
        session.send()
        await Support.settle(session)
        let request = try #require(model.requests.last?.decision)
        #expect(request.state.map(\.text) == ["Is 17 a prime number?"], "with no context, the question itself is the state")
        #expect(request.question == "Is 17 a prime number?")
        #expect(session.turns.last?.selections.isEmpty == true, "and nothing is quoted, since no context was added")
        #expect(session.turns.last?.decision == Self.yes)
    }

    @Test func theScopeSwitchExplainsItselfOnceClicked() async throws {
        let model = ScriptedModel(decisions: [Self.yes])
        let (session, preferences) = Self.decisionSession(model)
        #expect(session.explainedScope == nil, "never by itself")
        session.chooseScope(.words)
        #expect(preferences.decisionScope == .words)
        #expect(session.explainedScope == .words)
        session.chooseScope(.whole)
        #expect(session.explainedScope == .whole, "the whole text is explained too, once switched back to")
        session.draft = "Is this urgent?"
        session.send()
        await Support.settle(session)
        #expect(session.turns.count == 1)
        #expect(session.explainedScope == nil, "it goes with the question")
        session.chooseScope(.lines)
        session.reset()
        #expect(session.explainedScope == nil, "and with the chat")
        for scope in DecisionScope.allCases {
            #expect(scope.explanation.contains(scope == .whole ? "whole" : scope.noun), "\(scope) explained")
        }
    }

    @Test func textWrittenInTheWindowIsTheTextToDecideAbout() async throws {
        let unsure = Decision(options: [.init(label: "Yes", probability: 0.3), .init(label: "No", probability: 0.7)], isYesNo: true, confidence: 0.4)
        let model = ScriptedModel(decisions: [unsure])
        let (session, _) = Self.decisionSession(model)
        session.draft = "Is this spam?"
        #expect(session.needsDecisionState)
        session.writeState()
        #expect(session.typedState == "")
        #expect(session.canSend, "the question alone can be asked; context is optional")
        #expect(!session.needsDecisionState, "the card stands in the row's place")
        session.typedState = "You won a prize, click here."
        #expect(session.canSend)
        #expect(!session.needsDecisionState)
        session.send()
        await Support.settle(session)
        #expect(session.typedState == nil, "the card goes with the question")
        let turn = try #require(session.turns.last)
        #expect(turn.selections.map(\.isTyped) == [true])
        #expect(turn.selections.first?.sourceLabel == "Context")
        #expect(model.requests.last?.decision?.state.first?.text == "You won a prize, click here.")
        #expect(turn.answer == "Not sure, leaning No (40% confident)")
        #expect(turn.decision?.verdict(unsureBelow: 0.5) == .unsure)
        #expect(session.usage.summary(.day).unsureDecisions == 1)
        #expect(SelectedText.message("Q", about: turn.selections) == "<text>\nYou won a prize, click here.\n</text>\n\nQ")

        session.writeState()
        session.typedState = "Later"
        session.removeTypedState()
        #expect(session.typedState == nil)
        #expect(!session.needsDecisionState, "the chat keeps the text of its first question")
        session.writeState()
        session.typedState = "Stashed"
        session.reset()
        #expect(session.typedState == nil, "a new chat starts without it")
    }

    @Test func picturesStayOutOfADecisionAndFinderBringsNone() throws {
        let (session, preferences) = Self.decisionSession(ScriptedModel())
        session.bring(try #require(SelectedText("Hello there", appName: "Notes")))
        session.draft = "Is this a greeting?"
        #expect(session.canSend)
        session.attach(Support.image())
        #expect(session.pictureNotice == "A decision reads text only, not a picture. Switch to LLM to ask about it.")
        #expect(!session.canSend)
        preferences.mode = .llm
        #expect(session.pictureNotice == nil, "an LLM looks at the picture as it is")
        #expect(session.canSend)
        preferences.mode = .decision
        session.removeAttachment(try #require(session.draftImages.first?.id))
        #expect(session.canSend)
        session.bring(files: [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")])
        #expect(session.draftFiles.isEmpty && session.draftImages.isEmpty, "a decision reads text only")
        #expect(session.draftAnswers == .yesNo)
        session.draft = "Which is it? Greeting / Farewell"
        #expect(session.draftAnswers.options == ["Greeting", "Farewell"])
    }

    @Test func aGameIsNeverPlayedAgainstADecisionModel() {
        let (session, preferences) = Self.decisionSession(ScriptedModel())
        #expect(preferences.activeProvider == .typeSafe)
        session.startGame(.rhymeDuel)
        #expect(preferences.mode == .llm, "the toggle says who plays")
        #expect(preferences.activeProvider == .custom)
        #expect(session.isPlaying)
    }

    @Test func askingAgainAsksAboutTheSameText() async throws {
        let model = ScriptedModel(decisions: [Self.yes, Self.no])
        let (session, _) = Self.decisionSession(model)
        session.bring(try #require(SelectedText("Please send the report by noon.", appName: "Mail")))
        session.draft = "Is this urgent?"
        session.send()
        await Support.settle(session)
        session.askAgain()
        await Support.settle(session)
        #expect(model.requests.count == 2)
        #expect(model.requests.last?.decision?.state.map(\.text) == ["Please send the report by noon."])
        #expect(session.turns.count == 1)
        #expect(session.turns.last?.answer == "No (60% confident)")
        #expect(session.turns.last?.selections.count == 1, "the quote stays with the question")
    }

    // MARK: Settings

    @Test func eachModeHasPresetsOfItsOwn() throws {
        let defaults = Self.throwaway()
        let preferences = Self.preferences(defaults)
        #expect(preferences[presets: .llm] == PromptPreset.defaults(in: .english))
        #expect(preferences[presets: .agent].map(\.title) == ["Find Bugs", "Explain Code", "Write Tests", "Research"])
        #expect(preferences[presets: .decision].map(\.title) == ["Urgent?", "Scam?", "Tone", "Priority"])
        #expect(preferences[presets: .agent].allSatisfy { PromptPreset.exists($0.symbol) })
        #expect(preferences[presets: .decision].allSatisfy { PromptPreset.exists($0.symbol) })
        let tone = try #require(preferences[presets: .decision].first { $0.id == "tone" })
        #expect(DecisionAnswers.split(tone.text, fallback: .yesNo).answers.options == ["Friendly", "Neutral", "Angry"])
        let priority = try #require(preferences[presets: .decision].first { $0.id == "priority" })
        #expect(DecisionAnswers.split(priority.text, fallback: .yesNo).answers.isOrdered)
        preferences.mode = .decision
        #expect(preferences.presets == preferences[presets: .decision], "the panel's presets follow the mode")

        var changed = preferences[presets: .decision]
        changed.append(PromptPreset(id: "safe", title: "Safe?", symbol: "shield", text: "Is this safe to run?"))
        preferences[presets: .decision] = changed
        #expect(preferences.arePresetsChanged(for: .decision))
        #expect(!preferences.arePresetsChanged(for: .llm))
        #expect(preferences.changedPresetKinds == [.decision])
        #expect(defaults.data(forKey: "promptPresets.decision") != nil)
        #expect(defaults.data(forKey: PromptPreset.key) == nil, "the LLMs' list stays under its old key, untouched")
        let reloaded = Self.preferences(defaults)
        #expect(reloaded[presets: .decision] == changed)
        #expect(reloaded[presets: .llm] == PromptPreset.defaults(in: .english))
        reloaded[presets: .decision] = PromptPreset.decisionDefaults
        #expect(!reloaded.arePresetsChanged(for: .decision))
        #expect(defaults.data(forKey: "promptPresets.decision") == nil)
    }

    @Test func theNotSureLineAndTheAnswersAreKept() {
        let defaults = Self.throwaway()
        let preferences = Self.preferences(defaults)
        #expect(preferences.unsureBelow == Decision.defaultUnsureBelow)
        #expect(preferences.decisionAnswers == DecisionAnswers.defaultText)
        preferences.unsureBelow = 0.7
        preferences.decisionAnswers = "Keep / Toss"
        let reloaded = Self.preferences(defaults)
        #expect(reloaded.unsureBelow == 0.7)
        #expect(reloaded.decisionAnswers == "Keep / Toss")
        let session = ChatSession(preferences: reloaded, usage: UsageLedger(file: nil)) { _ in AsyncThrowingStream { $0.finish() } }
        #expect(session.defaultAnswers.options == ["Keep", "Toss"])
        reloaded.decisionAnswers = "nonsense"
        #expect(session.defaultAnswers == .yesNo, "answers that can't be read fall back to Yes and No")
        session.draft = "Is this fine? Good < Bad"
        #expect(session.draftAnswers.isOrdered)
        #expect(preferences.decisionScope == .whole)
        preferences.decisionScope = .lines
        #expect(Self.preferences(defaults).decisionScope == .lines, "the scope is kept")
    }

    // MARK: Each word or line

    @Test func aScopeSplitsTheTextsIntoWordsOrLines() throws {
        let notes = try #require(SelectedText("Buy milk, eggs and bread.\n\n  Call the bank!  \nBuy milk", appName: "Notes"))
        let typed = try #require(SelectedText.typed("Email “Anna” (again)… $100 e-mail don’t"))
        #expect(DecisionScope.whole.items(in: [notes, typed]).isEmpty)
        #expect(DecisionScope.lines.items(in: [notes, typed]) == ["Buy milk, eggs and bread.", "Call the bank!", "Buy milk", "Email “Anna” (again)… $100 e-mail don’t"], "trimmed, no empty line, each once")
        #expect(DecisionScope.words.items(in: [notes, typed]) == ["Buy", "milk", "eggs", "and", "bread", "Call", "the", "bank", "Email", "Anna", "again", "100", "e-mail", "don’t"], "the punctuation around a word left off, each word once")
        #expect(DecisionScope.words.items(in: [try #require(SelectedText("… — !!!"))]).isEmpty, "punctuation alone is no word")
        #expect(DecisionScope.allCases.allSatisfy { PromptPreset.exists($0.symbol) })
        #expect(DecisionScope(named: "Lines") == .lines && DecisionScope(named: "word") == .words && DecisionScope(named: "text") == .whole)
    }

    @Test func aQuestionAboutEachItemGoesInBatchesOfAHundred() throws {
        let words = (1...230).map { "w\($0)" }
        let request = DecisionRequest(state: [try #require(SelectedText(words.joined(separator: " "), appName: "Notes"))], question: "Is this a noun?", answers: .yesNo, scope: .words, items: words)
        let body = request.body(model: "jev-latest", itemsFrom: 200, count: DecisionScope.batchSize)
        let state = try #require(body["state"] as? [String: Any])
        #expect(state["items"] as? [String] == words, "the items go in the state, so a question can name its own")
        let questions = try #require(body["questions"] as? [String: [String: Any]])
        #expect(questions.count == 30, "the last batch takes what is left")
        let question = try #require(questions["item_229"])
        #expect(question["type"] as? String == "noul")
        let instructions = try #require(question["instructions"] as? [String: String])
        #expect(instructions == ["question": "Is this a noun?", "about": "items[229]", "item": "w230"])
        #expect(questions["item_199"] == nil && questions["item_230"] == nil)
        #expect(JSONSerialization.isValidJSONObject(body))
        #expect(request.body(model: "jev-latest")["questions"] as? [String: [String: Any]] != nil, "the whole text is still one question")

        let reply = Data("""
        {"model": "jev-1.13.0", "answers": {"item_200": {"type": "noul", "noul": 0.9}, "item_201": {"type": "noul", "noul": 0.1}}, "usage": {"input_tokens": 500, "output_tokens": 20}}
        """.utf8)
        let batch = try DecisionClient.decodeBatch(reply, for: request, from: 200, count: 2)
        #expect(batch.items.map(\.id) == [200, 201])
        #expect(batch.items.map(\.text) == ["w201", "w202"])
        #expect(batch.items[0].decision.chosen.label == "Yes" && batch.items[1].decision.chosen.label == "No")
        #expect(batch.usage == TokenUsage(input: 500, output: 20, model: "jev-1.13.0"))
        #expect(throws: (any Error).self) { try DecisionClient.decodeBatch(reply, for: request, from: 200, count: 3) }
    }

    @Test func aBatchGroupsItsItemsByAnswer() {
        func yes(_ p: Double) -> Decision { Decision(options: [.init(label: "Yes", probability: p), .init(label: "No", probability: 1 - p)], isYesNo: true, confidence: abs(2 * p - 1)) }
        let batch = DecisionBatch(scope: .words, answers: .yesNo, total: 4, items: [
            .init(id: 0, text: "apple", decision: yes(0.9)), .init(id: 1, text: "run", decision: yes(0.1)),
            .init(id: 2, text: "pear", decision: yes(0.8)), .init(id: 3, text: "blue", decision: yes(0.6)),
        ])
        #expect(batch.isComplete)
        #expect(batch.count == "4 words")
        let groups = batch.groups(unsureBelow: 0.5)
        #expect(groups.map(\.label) == ["Yes", "No", "Not sure"])
        #expect(groups.map(\.verdict) == [.yes, .no, .unsure])
        #expect(groups.map { $0.items.map(\.text) } == [["apple", "pear"], ["run"], ["blue"]])
        #expect(batch.summary(unsureBelow: 0.5) == "4 words: Yes 2 · No 1 · Not sure 1\n\nYes (2): apple, pear\n\nNo (1): run\n\nNot sure (1): blue")
        let lines = DecisionBatch(scope: .lines, answers: DecisionAnswers(options: ["Task", "Note"], isOrdered: false), total: 3, items: [
            .init(id: 0, text: "Buy milk", decision: Decision(options: [.init(label: "Task", probability: 0.9), .init(label: "Note", probability: 0.1)], confidence: 0.8)),
        ])
        #expect(!lines.isComplete)
        #expect(lines.groups(unsureBelow: 0.5).map(\.verdict) == [.chosen], "your own answers get no color")
        #expect(lines.summary(unsureBelow: 0.5) == "3 lines: Task 1\n\nTask (1):\n- Buy milk")
        #expect(DecisionBatch(scope: .lines, answers: .yesNo, total: 1, items: []).summary(unsureBelow: 0.5) == "1 line")
    }

    @Test func eachAnswersItemsComeSurestFirst() {
        func yes(_ p: Double) -> Decision { Decision(options: [.init(label: "Yes", probability: p), .init(label: "No", probability: 1 - p)], isYesNo: true, confidence: abs(2 * p - 1)) }
        let batch = DecisionBatch(scope: .words, answers: .yesNo, total: 7, items: [
            .init(id: 0, text: "apple", decision: yes(0.8)), .init(id: 1, text: "run", decision: yes(0.2)),
            .init(id: 2, text: "pear", decision: yes(0.95)), .init(id: 3, text: "blue", decision: yes(0.6)),
            .init(id: 4, text: "plum", decision: yes(0.8)), .init(id: 5, text: "jump", decision: yes(0.05)),
            .init(id: 6, text: "sky", decision: yes(0.35)),
        ])
        let groups = batch.groups(unsureBelow: 0.5)
        #expect(groups.map(\.label) == ["Yes", "No", "Not sure"])
        #expect(groups.map { $0.items.map(\.text) } == [["pear", "apple", "plum"], ["jump", "run"], ["sky", "blue"]], "surest first, ties in the text's order")
        #expect(batch.summary(unsureBelow: 0.5).contains("Yes (3): pear, apple, plum"), "Copy Answer lists them the same way")
    }

    @Test func aQuestionAboutEachLineIsAskedOfEveryLineAndCounted() async throws {
        func yes(_ p: Double) -> Decision { Decision(options: [.init(label: "Yes", probability: p), .init(label: "No", probability: 1 - p)], isYesNo: true, confidence: abs(2 * p - 1)) }
        let batch = DecisionBatch(scope: .lines, answers: .yesNo, total: 2, items: [.init(id: 0, text: "Call the bank", decision: yes(0.9)), .init(id: 1, text: "Buy milk", decision: yes(0.55))])
        let model = ScriptedModel(batches: [batch])
        let (session, preferences) = Self.decisionSession(model)
        preferences.decisionScope = .lines
        session.bring(try #require(SelectedText("Call the bank\nBuy milk", appName: "Notes")))
        session.draft = "Is this urgent?"
        #expect(session.canSend)
        session.send()
        await Support.settle(session)
        let request = try #require(model.requests.last?.decision)
        #expect(request.scope == .lines)
        #expect(request.items == ["Call the bank", "Buy milk"])
        let turn = try #require(session.turns.last)
        #expect(turn.decisions == batch)
        #expect(turn.decision == nil)
        #expect(turn.isDecision)
        #expect(turn.answer == "2 lines: Yes 1 · Not sure 1\n\nYes (1):\n- Call the bank\n\nNot sure (1):\n- Buy milk")
        #expect(!session.canRewrite)
        #expect(session.followUps.isEmpty)
        #expect(session.usage.summary(.day).decisions == 2, "one a line")
        #expect(session.usage.summary(.day).unsureDecisions == 1)

        // A text with nothing to split is decided about whole.
        let whole = ScriptedModel(decisions: [yes(0.9)])
        let (one, prefs) = Self.decisionSession(whole)
        prefs.decisionScope = .words
        one.bring(try #require(SelectedText("…", appName: "Notes")))
        one.draft = "Is this a word?"
        one.send()
        await Support.settle(one)
        #expect(whole.requests.last?.decision?.scope == .whole)
        #expect(one.turns.last?.decision != nil)
    }

    @Test func tooManyWordsWaitForTheWholeText() throws {
        let (session, preferences) = Self.decisionSession(ScriptedModel())
        preferences.decisionScope = .words
        session.bring(try #require(SelectedText((1...1_001).map { "w\($0)" }.joined(separator: " "), appName: "Notes")))
        session.draft = "Is this a noun?"
        #expect(session.bulkNotice == "A decision about each word takes up to \(1_000.formatted()) words, and the text has \(1_001.formatted()). Decide about the whole text instead, or about less of it.")
        #expect(!session.canSend)
        preferences.decisionScope = .lines
        #expect(session.bulkNotice == nil, "one line")
        preferences.decisionScope = .whole
        #expect(session.bulkNotice == nil)
        #expect(session.canSend)
    }
}
