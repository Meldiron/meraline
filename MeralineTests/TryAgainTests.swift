import Foundation
import Testing
@testable import Meraline

/// The way out of a failed answer: Try Again on the banner, and Ask Again first in the footer once an answer
/// failed partway. Until 2026-10-06 the banner offered nothing, and the footer went on saying Copy Answer.
@MainActor
struct TryAgainTests {
    private typealias Support = GameTestSupport

    private func context(_ session: ChatSession, preferences: Preferences) -> PanelContext {
        PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in })
    }

    /// A session whose first request streams `text` and then fails with `error`, and whose second answers whole.
    private func failing(with error: Error, after text: String?, then answer: String = "Whole.") -> (session: ChatSession, preferences: Preferences) {
        let preferences = Support.preferences()
        var asked = 0
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in
            asked += 1
            let first = asked == 1
            return AsyncThrowingStream { continuation in
                if first {
                    if let text { continuation.yield(.text(text)) }
                    continuation.finish(throwing: error)
                } else {
                    continuation.yield(.text(answer))
                    continuation.finish()
                }
            }
        }
        return (session, preferences)
    }

    @Test func anAnswerThatFailedPartwayIsAskedAgainFirst() async {
        let (session, preferences) = failing(with: LLMError.interrupted, after: "Half an ans")
        session.draft = "Tell me"
        session.send()
        await Support.settle(session)
        #expect(session.turns.last?.answer == "Half an ans")
        #expect(session.turns.last?.isComplete == true, "what came stays on screen")
        #expect(session.failure == LLMError.interrupted.localizedDescription)
        #expect(session.failureRetry == .askAgain)
        #expect(session.canTryAgain)

        let menu = context(session, preferences: preferences).chatMenu
        #expect(menu?.primary?.id == "askAgain", "asking again comes first")
        #expect(menu?.actions.filter { $0.id == "askAgain" }.count == 1)
        #expect(menu?.actions.contains { $0.id == "copyAnswer" } == true, "the cut-off answer can still be copied")

        session.tryAgain()
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["Whole."], "in the cut-off answer's place")
        #expect(session.failure == nil)
        #expect(!session.canTryAgain)
        #expect(context(session, preferences: preferences).chatMenu?.primary?.id == "copyAnswer")
    }

    @Test func aQuestionThatFailedBeforeAnyTextIsSentAgain() async {
        let (session, preferences) = failing(with: LLMError.http(500, "Boom"), after: nil)
        session.draft = "Tell me"
        session.send()
        await Support.settle(session)
        #expect(session.turns.isEmpty)
        #expect(session.draft == "Tell me", "the question came back to the input")
        #expect(session.failureRetry == .send)
        #expect(session.canTryAgain)
        #expect(context(session, preferences: preferences).chatMenu == nil, "no chat yet, so no footer")

        session.tryAgain()
        await Support.settle(session)
        #expect(session.turns.map(\.question) == ["Tell me"])
        #expect(session.turns.map(\.answer) == ["Whole."])
        #expect(session.draft.isEmpty)
        #expect(session.failure == nil)
    }

    @Test func aStoppedOrFinishedAnswerOffersCopyFirstAndNoTryAgain() async {
        let (session, preferences) = failing(with: CancellationError(), after: "Half")
        session.draft = "Tell me"
        session.send()
        await Support.settle(session)
        #expect(session.turns.last?.answer == "Half")
        #expect(session.failure == nil, "stopped isn't failed")
        #expect(!session.canTryAgain)
        #expect(context(session, preferences: preferences).chatMenu?.primary?.id == "copyAnswer")

        let whole = Support.session(ScriptedModel(["Paris."]))
        await Support.play("Capital of France?", in: whole)
        #expect(!whole.canTryAgain)
        #expect(context(whole, preferences: Support.preferences()).chatMenu?.primary?.id == "copyAnswer")
    }

    @Test func aSetupProblemIsForSettingsNotTryAgain() {
        let session = Support.session(ScriptedModel(["Paris."]), withProvider: false)
        session.draft = "Capital of France?"
        session.send()
        #expect(session.failure != nil)
        #expect(session.failureNeedsSettings)
        #expect(!session.canTryAgain)
    }

    @Test func aFailedAskAgainPutsTheOldAnswerBackAndAsksAgainOnTryAgain() async {
        let preferences = Support.preferences()
        var asked = 0
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in
            asked += 1
            let turn = asked
            return AsyncThrowingStream { continuation in
                switch turn {
                case 1: continuation.yield(.text("First.")); continuation.finish()
                case 2: continuation.finish(throwing: LLMError.http(503, "Busy"))
                default: continuation.yield(.text("Third.")); continuation.finish()
                }
            }
        }
        await Support.play("Tell me", in: session)
        session.askAgain()
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["First."], "the answer it was to replace is back")
        #expect(session.draft.isEmpty)
        #expect(session.failureRetry == .askAgain)
        session.tryAgain()
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["Third."])
    }
}
