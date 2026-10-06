import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Meraline

/// Improve on the Context card, in Decision mode while Live is on (`ContextImprovement`, `ChatSession.improveContext()`):
/// the answer each question's text should get, what the LLM reads, its reply read as the text alone, when the
/// button can take the text, the text replaced and the live decisions asked again, Undo, a text edited meanwhile
/// or given back as it was, a failure, and the count in the ledger.
@MainActor
struct ContextImprovementTests {
    private typealias Support = GameTestSupport

    private static let yesNo = DecisionAnswers.yesNo
    private static let tones = DecisionAnswers(options: ["Friendly", "Neutral", "Angry"], isOrdered: false)
    private static let levels = DecisionAnswers(options: ["Low", "Medium", "High"], isOrdered: true)

    private static func question(_ text: String, title: String? = nil, answers: DecisionAnswers = yesNo, id: String = "p") -> LiveQuestion {
        LiveQuestion(source: .preset(id), title: title ?? text, question: text, answers: answers, isOn: true)
    }

    private static let flirt = Decision(options: [.init(label: "Yes", probability: 0.65), .init(label: "No", probability: 0.35)], isYesNo: true, confidence: 0.3)
    private static let neutral = Decision(options: [.init(label: "Friendly", probability: 0.2), .init(label: "Neutral", probability: 0.7), .init(label: "Angry", probability: 0.1)], confidence: 0.7)

    // MARK: What the model is asked

    @Test func theGoalIsYesTheLastLevelOrTheAnswerTheTextHas() {
        #expect(ContextImprovement.goal(of: Self.question("Flirt?"), answered: Self.flirt) == "Yes")
        let noFirst = DecisionAnswers(options: ["No", "Yes"], isOrdered: false)
        #expect(ContextImprovement.goal(of: Self.question("Flirt?", answers: noFirst), answered: nil) == "Yes", "whatever order Settings lists them in")
        #expect(ContextImprovement.goal(of: Self.question("Priority?", answers: Self.levels), answered: nil) == "High")
        #expect(ContextImprovement.goal(of: Self.question("Tone?", answers: Self.tones), answered: Self.neutral) == "Neutral", "a list has no best answer, so the one it has")
        #expect(ContextImprovement.goal(of: Self.question("Tone?", answers: Self.tones), answered: nil) == "Friendly", "or the first before an answer came")
    }

    @Test func theModelReadsTheTextTheOtherTextsAndEachQuestionWithItsGoal() throws {
        let other = try #require(SelectedText(String(repeating: "m", count: ContextImprovement.otherTextLimit + 10), appName: "Mail"))
        let questions = [
            Self.question("Is this flirting?", title: "Flirt?", id: "flirt"),
            Self.question("What is the tone of this text?", title: "Tone", answers: Self.tones, id: "tone"),
            Self.question("How high a priority is this?", title: "Priority", answers: Self.levels, id: "priority"),
        ]
        let asked = ContextImprovement.question(
            text: " Hi there, nice to meet you. ", others: [other], questions: questions,
            answers: [questions[0].id: Self.flirt, questions[1].id: Self.neutral]
        )
        #expect(asked.contains("<text>\nHi there, nice to meet you.\n</text>"))
        #expect(asked.contains("which you cannot change:\n<text from=\"Mail\">\n" + String(repeating: "m", count: ContextImprovement.otherTextLimit) + "…\n</text>"))
        #expect(asked.contains("1. Is this flirting? (Flirt?)\n   Answers: Yes / No\n   Now: Yes 65%, No 35% (30% confident)\n   Should be: Yes"))
        #expect(asked.contains("2. What is the tone of this text? (Tone)\n   Answers: Friendly / Neutral / Angry\n   Now: Friendly 20%, Neutral 70%, Angry 10% (70% confident)\n   Should be: Neutral"))
        #expect(asked.contains("3. How high a priority is this? (Priority)\n   Answers, in order: Low < Medium < High\n   Now: not decided yet\n   Should be: High"))
        #expect(asked.hasSuffix("Reply with the edited text only."))

        let alone = ContextImprovement.question(text: "Hi", others: [], questions: [Self.question("Flirt?")], answers: [:])
        #expect(!alone.contains("cannot change"))
        #expect(alone.contains("1. Flirt?\n   Answers"), "a title that is the question isn't repeated")
    }

    @Test func theReplyIsReadAsTheTextAlone() {
        #expect(ContextImprovement.text(from: "  Hi there.\n", improving: "Hi.") == "Hi there.")
        #expect(ContextImprovement.text(from: "```\nHi there.\n```", improving: "Hi.") == "Hi there.")
        #expect(ContextImprovement.text(from: "```text\nHi there.\nBye.```", improving: "Hi.") == "Hi there.\nBye.")
        #expect(ContextImprovement.text(from: "\"Hi there.\"", improving: "Hi.") == "Hi there.")
        #expect(ContextImprovement.text(from: "“Hi there.”", improving: "Hi.") == "Hi there.")
        #expect(ContextImprovement.text(from: "\"Hi,\" she said. \"Bye.\"", improving: "\"Hi,\" she said.") == "\"Hi,\" she said. \"Bye.\"", "a text that begins with a quote keeps it")
        #expect(ContextImprovement.text(from: "```\nx\n```", improving: "```\nx\n```") == "```\nx\n```", "and one that begins with a fence")
        #expect(ContextImprovement.text(from: "\n\n", improving: "Hi.") == "")
    }

    @Test func improveReadsTheStreamAndCountsWhatItTook() async throws {
        var requests: [ChatRequest] = []
        let reply = try await ContextImprovement.improve(
            "Hi.", beside: [], toward: [Self.question("Flirt?")], answered: [:],
            provider: .custom, settings: ProviderSettings(model: "m", baseURL: "http://127.0.0.1:9", apiKey: "", isEnabled: true, allowsWebSearch: true, allowsMCP: true),
            stream: { request in
                requests.append(request)
                return AsyncThrowingStream { continuation in
                    continuation.yield(.text("Draft "))
                    continuation.yield(.activity(.searching("x")))
                    continuation.yield(.text("Hi "))
                    continuation.yield(.text("there."))
                    continuation.yield(.usage(TokenUsage(input: 40, output: 5), adds: false))
                    continuation.finish()
                }
            }
        )
        #expect(reply.text == "Hi there.", "words after a tool take the place of those before it")
        #expect(reply.usage == TokenUsage(input: 40, output: 5))
        let request = try #require(requests.first)
        #expect(request.systemPrompt == ContextImprovement.systemPrompt)
        #expect(!request.settings.allowsWebSearch && !request.settings.allowsMCP && request.workspace == nil)
        #expect(request.messages.count == 1 && request.messages[0].text.contains("<text>\nHi.\n</text>"))

        await #expect(throws: LLMError.self, "an empty reply is a failure, never an empty card") {
            try await ContextImprovement.improve("Hi.", beside: [], toward: [], answered: [:], provider: .custom, settings: ProviderSettings(model: "m", baseURL: "http://127.0.0.1:9", apiKey: "", isEnabled: true), stream: { _ in
                AsyncThrowingStream { $0.finish() }
            })
        }
    }

    // MARK: On the card

    /// A session in Decision mode with TypeSafe deciding live at once, through `decider`, and `model` as the LLM.
    private static func session(_ model: ScriptedModel, decider: LiveDecisionTests.ScriptedDecider = .init(), withLLM: Bool = true) -> (session: ChatSession, preferences: Preferences) {
        let preferences = Support.preferences(withProvider: withLLM)
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        preferences.mode = .decision
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { model.stream($0) }, decideLive: decider.decide)
        session.liveDecisions.isOn = true
        session.liveDecisions.debounce = 0.02
        session.liveDecisions.maxWait = 0.05
        return (session, preferences)
    }

    /// Waits out the live decisions and an improvement on its way.
    private static func settle(_ session: ChatSession) async {
        for _ in 0..<2_000 {
            guard session.isImprovingContext || !session.liveDecisions.pending.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func improveTakesTextWithAQuestionOnAndAnLLMToEditWith() async {
        let (session, preferences) = Self.session(ScriptedModel())
        #expect(session.improvementProvider == .custom)
        #expect(!session.canImproveContext, "the card is closed")
        session.writeState()
        #expect(!session.canImproveContext, "no text yet")
        session.typedState = "  "
        #expect(!session.canImproveContext, "spaces are no text")
        session.typedState = "Hi there."
        #expect(!session.canImproveContext, "nothing is asked")
        session.draft = "Is this flirting?"
        #expect(session.canImproveContext)
        session.draft = ""
        session.toggleLivePreset("tone")
        #expect(session.canImproveContext, "a preset on will do")
        session.liveDecisions.isOn = false
        #expect(!session.canImproveContext, "Live off")
        session.liveDecisions.isOn = true
        preferences.mode = .llm
        #expect(!session.canImproveContext, "another mode")
        preferences.mode = .decision
        #expect(session.canImproveContext)

        let withoutLLM = Self.session(ScriptedModel(), withLLM: false).session
        withoutLLM.writeState()
        withoutLLM.typedState = "Hi there."
        withoutLLM.draft = "Is this flirting?"
        #expect(withoutLLM.improvementProvider == nil && !withoutLLM.canImproveContext, "a decision model writes nothing")
    }

    @Test func improveReplacesTheTextAsksTheDecisionsAgainAndCounts() async throws {
        let decider = LiveDecisionTests.ScriptedDecider()
        decider.answers["Is this flirting?"] = Self.flirt
        let model = ScriptedModel(["Hi there, lovely to meet you."], usage: [TokenUsage(input: 50, output: 8)])
        let session = Self.session(model, decider: decider).session
        session.writeState()
        session.typedState = "Hi there, nice to meet you."
        session.draft = "Is this flirting?"
        await Self.settle(session)
        #expect(decider.asks.count == 1)

        session.improveContext()
        #expect(session.isImprovingContext && !session.canImproveContext, "one at a time")
        await Self.settle(session)
        #expect(!session.isImprovingContext)
        #expect(session.typedState == "Hi there, lovely to meet you.")
        #expect(session.draft == "Is this flirting?", "the question stays")
        #expect(session.turns.isEmpty, "no turn in the chat")

        // The LLM got the text, the question with its answer, and the goal, under Improve's prompt.
        let request = try #require(model.requests.last)
        #expect(request.provider == .custom && request.systemPrompt == ContextImprovement.systemPrompt)
        let asked = try #require(request.messages.last?.text)
        #expect(asked.contains("<text>\nHi there, nice to meet you.\n</text>"))
        #expect(asked.contains("1. Is this flirting?\n   Answers: Yes / No\n   Now: Yes 65%, No 35% (30% confident)\n   Should be: Yes"))

        // The decisions were asked about the new text at once, and the edit waits for Undo.
        #expect(decider.asks.count == 2 && decider.asks.last?.texts == ["Hi there, lovely to meet you."])
        #expect(session.canUndoContextImprovement)
        let note = try #require(session.improvementNote)
        #expect(note.hasPrefix("Improved: ") && note.contains("edit"), Comment(rawValue: note))

        // Counted under the LLM that edited, with its tokens, never as a question, an answer, or a rewrite.
        let tally = session.usage.summary(.day)
        #expect(tally.contextImprovements == 1 && tally.providers["custom"] == 1)
        #expect(tally.questions == 0 && tally.answers == 0 && tally.rewrites.isEmpty)
        #expect(tally.models["custom/games"]?.input == 50 && tally.models["custom/games"]?.output == 8)
        let data = try JSONEncoder().encode(tally)
        #expect(try JSONDecoder().decode(UsageTally.self, from: data).contextImprovements == 1, "and kept in the ledger's file")
    }

    @Test func undoPutsTheTextBackOneImprovementAtATime() async throws {
        let decider = LiveDecisionTests.ScriptedDecider()
        let model = ScriptedModel(["Hi there, lovely to meet you.", "Hi there, so lovely to meet you.", "Hi there, lovely to meet you."])
        let session = Self.session(model, decider: decider).session
        session.writeState()
        session.typedState = "Hi there."
        session.draft = "Is this flirting?"
        await Self.settle(session)
        session.improveContext()
        await Self.settle(session)
        session.improveContext()
        await Self.settle(session)
        #expect(session.typedState == "Hi there, so lovely to meet you." && session.contextImprovements.count == 2)
        let asks = decider.asks.count

        session.undoContextImprovement()
        #expect(session.typedState == "Hi there, lovely to meet you." && session.canUndoContextImprovement)
        #expect(session.improvementNote == "Improved: most of the text changed", "the one before still stands, and it kept little of two words")

        await Self.settle(session)
        #expect(decider.asks.count == asks + 1 && decider.asks.last?.texts == ["Hi there, lovely to meet you."], "decided about again")
        session.undoContextImprovement()
        #expect(session.typedState == "Hi there." && !session.canUndoContextImprovement && session.improvementNote == nil)
        session.undoContextImprovement()
        #expect(session.typedState == "Hi there.", "nothing left to undo")

        // An edit by hand ends the undo, and closing the card forgets it all.
        session.improveContext()
        await Self.settle(session)
        session.typedState = "Hi there, lovely to meet you. Coffee?"
        #expect(!session.canUndoContextImprovement && session.improvementNote == nil)
        #expect(session.contextImprovements.count == 1)
        session.removeTypedState()
        #expect(session.contextImprovements.isEmpty)
    }

    @Test func aTextEditedMeanwhileOrGivenBackAsItWasIsLeftAlone() async throws {
        let decider = LiveDecisionTests.ScriptedDecider()
        let preferences = Support.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        preferences.mode = .decision
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { _ in
            AsyncThrowingStream { continuation in
                Task {
                    try? await Task.sleep(for: .milliseconds(60))
                    continuation.yield(.text("Hi there, lovely to meet you."))
                    continuation.finish()
                }
            }
        }, decideLive: decider.decide)
        session.liveDecisions.isOn = true
        session.liveDecisions.debounce = 0.02
        session.liveDecisions.maxWait = 0.05
        session.writeState()
        session.typedState = "Hi there."
        session.draft = "Is this flirting?"
        await Self.settle(session)

        session.improveContext()
        session.typedState = "Hi there. Coffee?"
        await Self.settle(session)
        #expect(session.typedState == "Hi there. Coffee?", "what was typed wins")
        #expect(session.improvementNote == "The text changed meanwhile, so it was left as it is.")
        #expect(session.contextImprovements.isEmpty && !session.canUndoContextImprovement)
        session.typedState = "Hi there. Coffee? "
        #expect(session.improvementNote == nil, "the note goes with the next change")

        // The same text back: nothing to improve.
        session.typedState = "Hi there, lovely to meet you. "
        await Self.settle(session)
        session.improveContext()
        await Self.settle(session)
        #expect(session.typedState == "Hi there, lovely to meet you. ")
        #expect(session.improvementNote == "Custom found nothing to improve and left the text as it is.")
        #expect(session.contextImprovements.isEmpty)
        #expect(session.usage.summary(.day).contextImprovements == 2, "the requests still count")
    }

    @Test func aFailureShowsUntilTheTextChanges() async throws {
        let session = Self.session(ScriptedModel()).session
        session.writeState()
        session.typedState = "Hi there."
        session.draft = "Is this flirting?"
        await Self.settle(session)
        session.improveContext()
        await Self.settle(session)
        #expect(session.improvementNote != nil && session.typedState == "Hi there.", "an empty reply fails")
        #expect(session.canImproveContext, "and can be tried again")
        session.typedState = "Hi there!"
        #expect(session.improvementNote == nil)
    }

    @Test func liveTurnedOffDropsAnImprovementOnItsWay() async throws {
        let decider = LiveDecisionTests.ScriptedDecider()
        let preferences = Support.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        preferences.mode = .decision
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { _ in
            AsyncThrowingStream { continuation in
                Task {
                    try? await Task.sleep(for: .milliseconds(60))
                    continuation.yield(.text("Hi there, lovely to meet you."))
                    continuation.finish()
                }
            }
        }, decideLive: decider.decide)
        session.liveDecisions.isOn = true
        session.liveDecisions.debounce = 0.02
        session.liveDecisions.maxWait = 0.05
        session.writeState()
        session.typedState = "Hi there."
        session.draft = "Is this flirting?"
        await Self.settle(session)
        session.improveContext()
        session.toggleLiveDecisions()
        await Self.settle(session)
        #expect(session.typedState == "Hi there." && session.contextImprovements.isEmpty, "the card no longer decides, so nothing lands on it")
        #expect(session.improvementNote == nil)
    }

    /// The button sits in the header while Live is on, and the note with Undo takes a row under the capsules.
    @Test func theCardShowsImproveAndItsNote() async throws {
        let decider = LiveDecisionTests.ScriptedDecider()
        let (session, preferences) = Self.session(ScriptedModel(), decider: decider)
        session.writeState()
        session.typedState = "Hi there."
        session.draft = "Is this flirting?"
        await Self.settle(session)


        func height(_ improvement: ImproveStatus?) async throws -> CGFloat {
            var text = session.typedState ?? ""
            let binding = Binding(get: { text }, set: { text = $0 })
            let focus = FocusState<Bool>()
            let card = TypedStateCard(
                text: binding, isDeciding: true, live: session.liveDecisions, unsureBelow: preferences.unsureBelow,
                isFocused: focus.projectedValue, improvement: improvement, remove: {}
            )
            let host = NSHostingView(rootView: card.frame(width: 600))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
        let ready = ImproveStatus(isAvailable: true, isWorking: false, providerName: "Custom", note: nil, canUndo: false)
        let without = try await height(nil)
        let with = try await height(ready)
        #expect(abs(with - without) < 1, "the button shares the header's row: \(with) against \(without)")
        var improved = ready
        improved.note = "Improved: 12% changed · 2 edits"
        improved.canUndo = true
        let noted = try await height(improved)
        #expect(noted > with + 10, "the note takes a row: \(noted) against \(with)")
    }
}
