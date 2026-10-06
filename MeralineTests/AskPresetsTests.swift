import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Meraline

/// The circle at the end of Decision's presets (see `PromptPresets`, `ChatSession.askPresets(_:)`): every preset
/// asked at once about the draft's texts, in one turn and one request, each answer on the card as it comes, what
/// the ledger counts, Ask Again and Try Again, and when the circle can't ask.
@MainActor
struct AskPresetsTests {
    private typealias Support = GameTestSupport
    private let presets = PromptPreset.decisionDefaults

    private static let yes = Decision(options: [.init(label: "Yes", probability: 0.91), .init(label: "No", probability: 0.09)], isYesNo: true, confidence: 0.82)
    private static let no = Decision(options: [.init(label: "Yes", probability: 0.2), .init(label: "No", probability: 0.8)], isYesNo: true, confidence: 0.6)
    private static let neutral = Decision(options: [.init(label: "Friendly", probability: 0.2), .init(label: "Neutral", probability: 0.7), .init(label: "Angry", probability: 0.1)], confidence: 0.7)
    private static let high = Decision(options: [.init(label: "Low", probability: 0.1), .init(label: "Medium", probability: 0.2), .init(label: "High", probability: 0.7)], isOrdered: true, score: 1.8, confidence: 0.65)

    /// A session in Decision mode with TypeSafe ready.
    private static func session(_ model: ScriptedModel) -> (session: ChatSession, preferences: Preferences) {
        let preferences = Support.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        preferences.mode = .decision
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        return (session, preferences)
    }

    @Test func everyPresetIsAskedAtOnceAboutTheTexts() async throws {
        let model = ScriptedModel(decisions: [Self.yes, Self.no, Self.neutral, Self.high])
        let (session, _) = Self.session(model)
        #expect(!session.canAskPresets(among: presets), "nothing to decide about yet")
        session.bring(try #require(SelectedText("Production is down, fix it now", appName: "Mail")))
        session.draft = "Is it my fault?"
        #expect(session.canAskPresets(among: presets))
        session.askPresets(presets)
        #expect(session.isStreaming)
        #expect(session.turns.first?.presetDecisions?.questions.map(\.title) == ["Urgent?", "Scam?", "Tone", "Priority"], "the card shows what is asked at once")
        #expect(session.turns.first?.presetDecisions?.isComplete == false)
        await Support.settle(session)
        #expect(session.turns.count == 1)
        let turn = try #require(session.turns.first)
        #expect(turn.question == "Urgent? · Scam? · Tone · Priority")
        #expect(turn.selections.map(\.sourceLabel) == ["Mail"])
        #expect(session.draft == "Is it my fault?", "what is typed stays, for a follow-up")
        #expect(session.typedState == nil)
        #expect(session.draftSelections.isEmpty)
        let round = try #require(turn.presetDecisions)
        #expect(round.isComplete)
        #expect(round.questions.map(\.decision) == [Self.yes, Self.no, Self.neutral, Self.high])
        #expect(turn.isDecision && turn.isComplete)
        #expect(turn.answer == "- Urgent?: Yes (82% confident)\n- Scam?: No (60% confident)\n- Tone: Neutral (70% confident)\n- Priority: High (65% confident)")

        // One request carrying every question, named by its preset, about the text.
        let request = try #require(model.requests.last?.decision)
        let asked = try #require(request.presets)
        #expect(asked.questions.map(\.id) == ["urgent", "scam", "tone", "priority"])
        #expect(asked.undecided.map(\.question) == ["Is this urgent?", "Is this a scam, spam, or phishing?", "What is the tone of this text?", "How high a priority is this?"])
        #expect(asked.undecided.map(\.answers.options) == [["Yes", "No"], ["Yes", "No"], ["Friendly", "Neutral", "Angry"], ["Low", "Medium", "High"]])
        #expect(asked.undecided.map(\.answers.isOrdered) == [false, false, false, true])
        #expect(request.state.map(\.text) == ["Production is down, fix it now"])
        let body = DecisionRequest.body(model: "jev-latest", state: request.state, questions: asked.undecided)
        let questions = try #require(body["questions"] as? [String: Any])
        #expect(Set(questions.keys) == ["urgent", "scam", "tone", "priority"])
        #expect(DecisionClient.batches(of: asked.undecided, for: .ollamaDecision).count == 1, "four fit one of Ollama's requests")

        // The ledger: one question, one answer, four decisions, none of them live.
        let tally = session.usage.summary(.day)
        #expect(tally.questions == 1 && tally.answers == 1 && tally.chats == 1)
        #expect(tally.decisions == 4 && tally.unsureDecisions == 0 && tally.liveDecisions == 0)
        #expect(tally.selections == 1)
        #expect(session.followUps.isEmpty && !session.canRewrite)
        #expect(!session.canAskPresets(among: presets), "the presets are for an empty chat")
    }

    @Test func aPresetWithoutAQuestionIsLeftOutAndSettingsAnswersStandIn() {
        let fallback = DecisionAnswers(options: ["Sure", "Nah"], isOrdered: false)
        let round = PresetDecisions(presets: [
            PromptPreset(id: "blank", title: "Blank", symbol: "star", text: "  "),
            PromptPreset(id: "ok", title: "", symbol: "star", text: "Is this ok?"),
            PromptPreset(id: "which", title: "Which", symbol: "star", text: "Which one? A / B"),
        ], fallback: fallback)
        #expect(round.questions.map(\.id) == ["ok", "which"])
        #expect(round.questions[0].title == "Is this ok?", "a preset without a title wears its question")
        #expect(round.questions[0].answers == fallback)
        #expect(round.questions[1].question == "Which one?" && round.questions[1].answers.options == ["A", "B"])
        #expect(round.headline == "Is this ok? · Which")
        #expect(!round.isComplete && round.decided.isEmpty && round.undecided.count == 2)
        #expect(round.summary(unsureBelow: 0.5) == "- Is this ok?: not decided\n- Which: not decided")
        var filled = round
        filled.take(["ok": Self.yes, "stray": Self.no])
        #expect(!filled.isComplete && filled.undecided.map(\.id) == ["which"] && filled.decided == [Self.yes])
        #expect(filled.summary(unsureBelow: 0.9) == "- Is this ok?: Not sure, leaning Yes (82% confident)\n- Which: not decided")
        #expect(filled.cleared == round)
        #expect(PresetDecisions(presets: [], fallback: fallback).isEmpty)
    }

    @Test func theCircleWaitsForTextAndADecisionModel() throws {
        let (session, preferences) = Self.session(ScriptedModel())
        #expect(!session.canAskPresets(among: presets))
        session.writeState()
        #expect(!session.canAskPresets(among: presets), "an empty card is no text")
        session.typedState = "Production is down"
        #expect(session.canAskPresets(among: presets))
        #expect(!session.canAskPresets(among: []))
        #expect(!session.canAskPresets(among: [PromptPreset(id: "blank", title: "Blank", symbol: "star", text: "")]))
        preferences.mode = .llm
        #expect(!session.canAskPresets(among: presets), "only a decision model decides")
        preferences.mode = .decision
        #expect(session.canAskPresets(among: presets))
        session.bring(Support.image())
        #expect(!session.canAskPresets(among: presets), "a picture waits on Switch to LLM")
        session.askPresets(presets)
        #expect(session.turns.isEmpty && !session.isStreaming)
    }

    @Test func askAgainAsksThemAllAgainAndAFailureOffersTryAgain() async throws {
        let model = ScriptedModel(decisions: [Self.yes, Self.no, Self.neutral, Self.high, Self.no, Self.no, Self.neutral, Self.high])
        let (session, _) = Self.session(model)
        let mail = try #require(SelectedText("Production is down", appName: "Mail"))
        session.bring(mail)
        session.askPresets(presets)
        await Support.settle(session)
        #expect(session.canAskAgain)
        session.askAgain()
        #expect(session.turns.first?.presetDecisions?.isComplete == false, "every question open again")
        await Support.settle(session)
        #expect(session.turns.count == 1)
        #expect(session.turns[0].presetDecisions?.questions.map(\.decision) == [Self.no, Self.no, Self.neutral, Self.high])
        #expect(model.requests.last?.decision?.presets?.undecided.count == 4)
        #expect(session.turns[0].selections.map(\.sourceLabel) == ["Mail"], "about the same text")
        #expect(session.usage.summary(.day).decisions == 8)

        // No answer at all: the text comes back to the draft, the input is left as it was, and Try Again asks
        // every preset again.
        let failing = ScriptedModel()
        let (second, _) = Self.session(failing)
        second.bring(mail)
        second.draft = "Is it my fault?"
        second.askPresets(presets)
        await Support.settle(second)
        #expect(second.turns.isEmpty)
        #expect(second.failure != nil)
        #expect(second.draft == "Is it my fault?", "the presets' line never lands in the input")
        #expect(second.draftSelections.map(\.sourceLabel) == ["Mail"])
        #expect(second.canTryAgain)
        failing.decisions = [Self.yes, Self.no, Self.neutral, Self.high]
        second.tryAgain()
        await Support.settle(second)
        #expect(second.turns.count == 1)
        #expect(second.turns[0].presetDecisions?.isComplete == true)
        #expect(second.failure == nil && !second.canTryAgain)
    }

    /// The card lays out in the real panel while the answers come and once they are in.
    @Test func theCardDrawsARowForEachPreset() async throws {
        let (session, preferences) = Self.session(ScriptedModel(decisions: [Self.yes, Self.no, Self.neutral, Self.high]))
        session.bring(try #require(SelectedText("Production is down", appName: "Mail")))
        session.askPresets(presets)
        await Support.settle(session)
        let round = try #require(session.turns.first?.presetDecisions)
        let card = PresetDecisionsCard(round: round, unsureBelow: preferences.unsureBelow, isAnswering: false)
        let host = NSHostingView(rootView: card.frame(width: 420))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 100, "four rows take room: \(host.fittingSize.height)")
        let open = PresetDecisionsCard(round: round.cleared, unsureBelow: preferences.unsureBelow, isAnswering: true)
        let waiting = NSHostingView(rootView: open.frame(width: 420))
        waiting.layoutSubtreeIfNeeded()
        #expect(waiting.fittingSize.height > 100)
    }
}
