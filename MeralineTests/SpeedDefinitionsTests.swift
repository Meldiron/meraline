import Foundation
import Testing
@testable import Meraline

@MainActor
struct SpeedDefinitionsTests {
    private typealias Support = GameTestSupport
    private typealias Word = SpeedDefinitions.Word

    private static let serendipity = "serendipity | finding something good without looking for it"

    @Test func wordsInMostShapes() {
        let expected = Word(word: "serendipity", meaning: "finding something good without looking for it")
        #expect(SpeedDefinitions.word(from: Self.serendipity) == expected)
        #expect(SpeedDefinitions.word(from: "serendipity: finding something good without looking for it.") == expected)
        #expect(SpeedDefinitions.word(from: "serendipity\nfinding something good without looking for it") == expected)
        #expect(SpeedDefinitions.word(from: "Word: **serendipity** | finding something good without looking for it.") == expected)
        #expect(SpeedDefinitions.word(from: "serendipity") == Word(word: "serendipity"))
        #expect(SpeedDefinitions.word(from: "Here is a lovely word for you to define today") == nil)
        #expect(SpeedDefinitions.word(from: "") == nil)
    }

    @Test func gradesInMostShapes() {
        #expect(SpeedDefinitions.grade(from: "8/10 — nails the luck part.") == .init(score: 8, comment: "nails the luck part"))
        #expect(SpeedDefinitions.grade(from: "Nice one!\nScore: 6 out of 10") == .init(score: 6))
        #expect(SpeedDefinitions.grade(from: "7/10\nclose, but it misses the luck") == .init(score: 7, comment: "close, but it misses the luck"))
        #expect(SpeedDefinitions.grade(from: "Great definition") == nil)
    }

    @Test func aDefinitionIsCheckedBeforeAsking() {
        let turns = [Support.turn(cue: SpeedDefinitions.opening, reply: Self.serendipity)]
        #expect(SpeedDefinitions.play("a happy accident", in: turns, insisting: false) == .ask("a happy accident"))
        #expect(SpeedDefinitions.play("one two three four five six seven eight nine ten eleven", in: turns, insisting: false)
            == .reject("Ten words at most, and that was 11. Trim it down."))
        #expect(SpeedDefinitions.play("pure serendipity", in: turns, insisting: false) == .reject("Define “serendipity” without using it."))
        #expect(SpeedDefinitions.play("pass", in: turns, insisting: false)
            == .record("pass", outcome: GameOutcome(text: "Passed. It means finding something good without looking for it.", youWon: false)))
        #expect(SpeedDefinitions.play("a happy accident", in: [], insisting: false) == .reject("Wait for the word."))
    }

    @Test func fiveWordsMakeAGame() async {
        let model = ScriptedModel([
            Self.serendipity, "8/10 — nails the luck part",
            "gregarious | fond of company", "3/10 — too thin",
            "ephemeral | lasting a very short time",
            "petrichor | the smell of rain on dry earth", "7/10 — close enough",
            "ubiquitous | found everywhere", "10/10 — spot on"
        ])
        let session = Support.session(model)
        session.startGame(.speedDefinitions)
        await Support.settle(session)
        #expect(model.requests.first?.systemPrompt == SpeedDefinitions.systemPrompt)
        #expect(session.gameState?.phase == .yourMove(placeholder: "Define “serendipity” in ten words or fewer…"))
        #expect(SpeedDefinitions.lines(for: session.turns).map(\.text) == ["Word 1", "serendipity"], "the model’s own definition stays hidden")

        await Support.play("a happy accident", in: session)
        #expect(model.lastMessages == [SpeedDefinitions.opening, Self.serendipity, "a happy accident"])
        #expect(SpeedDefinitions.lines(for: session.turns).map(\.text)
            == ["Word 1", "serendipity · finding something good without looking for it", "a happy accident", "8/10 · nails the luck part"])
        #expect(session.gameState?.status == "Word 2 of 5 · 8 points")

        session.send()
        await Support.settle(session)
        await Support.play("friendly", in: session)
        session.send()
        await Support.settle(session)
        await Support.play("pass", in: session)
        #expect(session.gameState?.status == "Word 4 of 5 · 11 points", "a pass asks for the next word at once")
        await Support.play("rain smell", in: session)
        session.send()
        await Support.settle(session)
        await Support.play("everywhere at once", in: session)

        #expect(session.nudge == "Game done: 28 of 50 points, and 3 of 5 definitions landed.")
        guard case .over(let outcome, let rematch)? = session.gameState?.phase else {
            Issue.record("five words should end the game")
            return
        }
        #expect(outcome.youWon == true)
        #expect(rematch.cue == SpeedDefinitions.newGame)
        #expect(session.conversationMarkdown?.hasPrefix("serendipity: finding something good without looking for it\nYou: a happy accident (8/10 · nails the luck part)") == true)
    }

    @Test func aMissingGradeSendsTheDefinitionBack() async {
        let model = ScriptedModel([Self.serendipity, "What a lovely try!"])
        let session = Support.session(model)
        session.startGame(.speedDefinitions)
        await Support.settle(session)
        await Support.play("a happy accident", in: session)
        #expect(session.nudge == "The model forgot to grade your definition. Press Return to send it again.")
        #expect(session.draft == "a happy accident")
        #expect(session.isYourMove)
    }
}
