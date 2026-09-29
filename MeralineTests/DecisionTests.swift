import AppKit
import Foundation
import Testing
@testable import Meraline

/// Decision mode: the answers a question names, the request TypeSafe's Jev gets and the reply it sends, and what
/// the chat does with a decision. It refuses to ask without text, keeps the text for follow-ups, writes the
/// answer in words, offers no rewrite, and plays no game against Jev.
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
        #expect(ProviderKind.decision.providers == [.typeSafe])
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

    @Test func aDecisionNeedsTextAndKeepsItForFollowUps() async throws {
        let model = ScriptedModel(decisions: [Self.yes, Self.no])
        let (session, _) = Self.decisionSession(model)
        session.draft = "Is this urgent?"
        #expect(session.isDeciding)
        #expect(!session.canSend, "nothing to decide about")
        #expect(session.needsDecisionState)
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

    @Test func textWrittenInTheWindowIsTheTextToDecideAbout() async throws {
        let unsure = Decision(options: [.init(label: "Yes", probability: 0.3), .init(label: "No", probability: 0.7)], isYesNo: true, confidence: 0.4)
        let model = ScriptedModel(decisions: [unsure])
        let (session, _) = Self.decisionSession(model)
        session.draft = "Is this spam?"
        session.writeState()
        #expect(session.typedState == "")
        #expect(!session.canSend, "an empty card is no text")
        #expect(session.needsDecisionState)
        session.typedState = "You won a prize, click here."
        #expect(session.canSend)
        #expect(!session.needsDecisionState)
        session.send()
        await Support.settle(session)
        #expect(session.typedState == nil, "the card goes with the question")
        let turn = try #require(session.turns.last)
        #expect(turn.selections.map(\.isTyped) == [true])
        #expect(turn.selections.first?.sourceLabel == "Written here")
        #expect(model.requests.last?.decision?.state.first?.text == "You won a prize, click here.")
        #expect(turn.answer == "Not sure, leaning No (40% confident)")
        #expect(turn.decision?.verdict(unsureBelow: 0.5) == .unsure)
        #expect(session.usage.summary(.day).unsureDecisions == 1)
        #expect(SelectedText.message("Q", about: turn.selections) == "<text>\nYou won a prize, click here.\n</text>\n\nQ")

        session.writeState()
        session.typedState = "Later"
        session.removeTypedState()
        #expect(session.typedState == nil)
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
    }
}
