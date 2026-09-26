import Foundation
import Testing
@testable import Meraline

@MainActor
struct RematchTrayTests {
    private typealias Support = GameTestSupport

    @Test func theTallyReadsAsAScore() {
        var versus = Versus()
        #expect(versus.tally == nil)
        versus.record(GameOutcome(text: "", youWon: nil))
        #expect(versus.tally == "1 round played", "a round nobody wins is just played")
        versus.record(GameOutcome(text: "", youWon: true))
        versus.record(GameOutcome(text: "", youWon: true))
        versus.record(GameOutcome(text: "", youWon: false))
        #expect(versus.tally == "You 2 – 1 Model · 1 draw")
    }

    /// Word Football, won by the model's foul: "salmon" doesn't start with the E of "apple".
    private func wonMatch(_ model: ScriptedModel) async -> ChatSession {
        let session = Support.session(model)
        session.startGame(.wordFootball)
        await Support.settle(session)
        await Support.play("apple", in: session)
        return session
    }

    @Test func playAgainFollowsARoundAndTheGame() async {
        let model = ScriptedModel(["Banana.", "OK: salmon", "Kettle", "Mango"])
        let session = await wonMatch(model)
        let over = session.rematch
        #expect(over?.game == .wordFootball)
        #expect(over?.isAfterGame == false)
        #expect(over?.message == "Foul! “salmon” doesn’t start with “E”. You win!")
        #expect(over?.versus.tally == "You 1 – 0 Model")

        session.playAgain()
        await Support.settle(session)
        #expect(session.turns.last?.cue == WordFootball.rematchCue, "Play Again is Return once a round is over")
        #expect(session.rematch == nil, "nothing to offer mid-match")

        session.reset()
        let after = session.rematch
        #expect(after?.game == .wordFootball)
        #expect(after?.isAfterGame == true)
        #expect(after?.message == "Word Football")
        #expect(after?.versus.tally == "You 1 – 0 Model", "the tally outlives the game")

        session.playAgain()
        await Support.settle(session)
        #expect(session.game == .wordFootball)
        #expect(session.turns.last?.reply == "mango")
        #expect(session.rematch == nil)
    }

    @Test func theTrayCanBePutAwayAndTheTallyStays() async {
        let session = await wonMatch(ScriptedModel(["Banana.", "OK: salmon"]))
        session.reset()
        session.putAwayRematch()
        #expect(session.rematch == nil)
        #expect(session.versus[.wordFootball]?.rounds == 1)
    }

    @Test func reopeningAGameCountsNothingTwice() async throws {
        let session = await wonMatch(ScriptedModel(["Banana.", "OK: salmon"]))
        session.reset()
        let past = try #require(session.history.first)
        session.reopen(past.id)
        #expect(session.rematch?.isAfterGame == false, "the round is still over")
        #expect(session.nudge == "Foul! “salmon” doesn’t start with “E”. You win!")
        #expect(session.versus[.wordFootball]?.rounds == 1)
    }

    @Test func aChatHidesTheTrayUntilItEnds() async {
        let model = ScriptedModel(["Banana.", "OK: salmon", "Paris."])
        let session = await wonMatch(model)
        session.reset()
        session.draft = "What is the capital of France?"
        session.send()
        await Support.settle(session)
        #expect(session.rematch == nil)
        session.reset()
        #expect(session.rematch?.game == .wordFootball)
    }
}
