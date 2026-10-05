import Foundation
import Testing
@testable import Meraline

@MainActor
struct RewriteTests {
    private typealias Support = GameTestSupport

    private func context(_ session: ChatSession) -> PanelContext {
        PanelContext(session: session, preferences: Support.preferences(), layout: PanelLayout(), openSettings: { _ in })
    }

    @Test func eachRewriteAsksForOnlyTheNewAnswer() {
        #expect(Set(Rewrite.allCases.map(\.title)).count == Rewrite.allCases.count)
        #expect(Set(Rewrite.allCases.map(\.instruction)).count == Rewrite.allCases.count)
        for rewrite in Rewrite.allCases {
            #expect(rewrite.instruction.hasPrefix("Rewrite your last answer"))
            #expect(rewrite.instruction.contains("Reply with only the rewritten answer"))
        }
    }

    @Test func aRewriteTakesTheLastAnswersPlaceAndKeepsTheInput() async {
        let model = ScriptedModel(["A long answer about DNS.", "DNS finds addresses."])
        let session = Support.session(model)
        await Support.play("What is DNS?", in: session)
        session.draft = "half a follow-up"
        #expect(session.canRewrite)
        session.rewrite(.shorter)
        await Support.settle(session)
        #expect(session.turns.map(\.question) == ["What is DNS?"])
        #expect(session.turns.map(\.answer) == ["DNS finds addresses."])
        #expect(session.turns.first?.isComplete == true)
        #expect(session.draft == "half a follow-up")
        #expect(model.lastMessages == ["What is DNS?", "A long answer about DNS.", Rewrite.shorter.instruction])
    }

    @Test func whatFollowsReadsTheRewrittenAnswer() async {
        let model = ScriptedModel(["A long answer.", "Short.", "- Short.", "Sure."])
        let session = Support.session(model)
        await Support.play("Explain", in: session)
        session.rewrite(.shorter)
        await Support.settle(session)
        session.rewrite(.bulletList)
        await Support.settle(session)
        #expect(model.lastMessages == ["Explain", "Short.", Rewrite.bulletList.instruction])
        await Support.play("Thanks", in: session)
        #expect(model.lastMessages == ["Explain", "- Short.", "Thanks"])
    }

    @Test func aRewriteKeepsWhatTheQuestionCarried() async throws {
        let model = ScriptedModel(["It's black.", "Black."])
        let session = Support.session(model)
        session.attach(Support.image())
        session.bring(try #require(SelectedText.clipboard("a black square")))
        await Support.play("What colour?", in: session)
        session.rewrite(.shorter)
        await Support.settle(session)
        let turn = try #require(session.turns.first)
        #expect(turn.answer == "Black.")
        #expect(turn.images.count == 1)
        #expect(turn.selections.count == 1)
        let request = try #require(model.requests.last)
        #expect(request.messages.first?.images.count == 1, "the image stays with the question it came with")
        #expect(request.messages.last?.images.isEmpty == true)
    }

    @Test func aFailedRewriteBringsTheOldAnswerBack() async {
        let session = Support.session(ScriptedModel(["The answer."]))
        await Support.play("Question?", in: session)
        session.draft = "typing"
        session.rewrite(.simpler)
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["The answer."])
        #expect(session.turns.first?.isComplete == true)
        #expect(session.draft == "typing")
        #expect(session.failure != nil)
    }

    @Test func aRewriteStoppedOrFailedPartwayBringsTheOldAnswerBack() async {
        for fails in [false, true] {
            var calls = 0
            let session = ChatSession(preferences: Support.preferences()) { _ in
                calls += 1
                let call = calls
                return AsyncThrowingStream { continuation in
                    if call == 1 {
                        continuation.yield(.text("The whole answer."))
                        continuation.finish()
                    } else {
                        continuation.yield(.text("Half"))
                        if fails { continuation.finish(throwing: LLMError.emptyResponse) }
                    }
                }
            }
            await Support.play("Question?", in: session)
            session.rewrite(.shorter)
            if !fails {
                for _ in 0..<100 where session.turns.last?.answer != "Half" { await Task.yield() }
                #expect(session.turns.last?.answer == "Half")
                session.stop()
            }
            await Support.settle(session)
            #expect(session.turns.map(\.answer) == ["The whole answer."])
            #expect(session.turns.first?.isComplete == true)
            #expect((session.failure != nil) == fails)
        }
    }

    @Test func undoRewriteBringsTheReplacedAnswerBack() async throws {
        let model = ScriptedModel(["A long answer about DNS.", "DNS finds addresses.", "- DNS finds addresses.", "Sure."])
        let session = Support.session(model)
        session.followUpSuggester = { request in ["About \(request.answer.prefix(6))?"] }
        await Support.play("What is DNS?", in: session)
        #expect(!session.canUndoRewrite, "nothing replaced yet")
        #expect(context(session).chatMenu?.actions.contains { $0.id == "undoRewrite" } == false)

        session.rewrite(.shorter)
        await Support.settle(session)
        session.rewrite(.bulletList)
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["- DNS finds addresses."])
        #expect(session.canUndoRewrite)
        session.draft = "half a follow-up"

        let undo = try #require(context(session).chatMenu?.actions.first { $0.id == "undoRewrite" })
        undo.perform()
        #expect(session.turns.map(\.answer) == ["DNS finds addresses."], "the rewrite before the last")
        #expect(session.turns.first?.isComplete == true)
        #expect(session.draft == "half a follow-up")
        #expect(session.canUndoRewrite, "and the first rewrite can go too")
        session.undoRewrite()
        #expect(session.turns.map(\.answer) == ["A long answer about DNS."])
        #expect(!session.canUndoRewrite)
        for _ in 0..<50 { await Task.yield() }
        #expect(session.followUps == ["About A long?"], "the follow-ups are the old answer's again")

        // The next question reads the answer that is back, and leaves nothing to undo.
        await Support.play("Really?", in: session)
        #expect(model.lastMessages.contains("A long answer about DNS."))
        #expect(!model.lastMessages.contains("DNS finds addresses."))
        #expect(!session.canUndoRewrite)
    }

    @Test func aFailedRewriteLeavesNothingToUndoAndANewChatForgets() async {
        let model = ScriptedModel(["First.", "Second."])
        let session = Support.session(model)
        await Support.play("Go", in: session)
        session.rewrite(.longer)
        await Support.settle(session)
        #expect(session.canUndoRewrite)
        session.reset()
        #expect(!session.canUndoRewrite, "a new chat starts with nothing to undo")
        session.reopen(session.history.first!.id)
        #expect(!session.canUndoRewrite, "and a reopened one too: the replaced answer lived with the open chat")
    }

    @Test func theChatsPanelOffersRewritesOnlyForAFinishedAnswer() async throws {
        let waiting = ChatSession(preferences: Support.preferences()) { _ in AsyncThrowingStream { _ in } }
        waiting.draft = "Tell me a story"
        waiting.send()
        #expect(!waiting.canRewrite)
        #expect(context(waiting).chatMenu?.actions.contains { $0.id.hasPrefix("rewrite.") } == false)

        let game = Support.session(ScriptedModel(["A cat sat waiting by the door | floor, more, four"]))
        game.startGame(.rhymeDuel)
        await Support.settle(game)
        #expect(!game.canRewrite)

        let model = ScriptedModel(["Paris is the capital of France.", "Paris, for example."])
        let session = Support.session(model)
        await Support.play("Capital of France?", in: session)
        let context = context(session)
        let concrete = try #require(context.chatMenu?.actions.first { $0.id == "rewrite.concrete" })
        #expect(concrete.title == "Make More Concrete")
        context.run(concrete, in: .chat)
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["Paris, for example."])
        #expect(context.layout.focusRequest == 1)
    }
}
