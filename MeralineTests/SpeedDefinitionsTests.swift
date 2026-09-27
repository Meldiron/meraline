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

    @Test func eachWordIsPickedFromThreeOfOneDifficultyTheChatHasntPlayed() throws {
        let all = SpeedDefinitions.Difficulty.allCases.flatMap(\.words)
        #expect(Set(all.map(GameText.key)).count == all.count, "no word twice, nor in two difficulties")
        #expect(all.allSatisfy { SpeedDefinitions.word(from: $0)?.word == $0 }, "each reads back as one word")
        var dice = GameDice(seed: 11)
        for cue in [SpeedDefinitions.opening, SpeedDefinitions.nextWord, SpeedDefinitions.newGame] {
            let aside = try #require(SpeedDefinitions.aside(for: Support.turn(cue: cue), after: [], dice: &dice))
            #expect(aside.hasPrefix("Pick one of these words, all of "))
            var turn = Support.turn(cue: cue)
            turn.aside = aside
            let difficulty = try #require(SpeedDefinitions.Difficulty(of: turn))
            #expect(difficulty.words.filter { aside.contains("“\($0)”") }.count == SpeedDefinitions.offeredCount)
        }
        #expect(SpeedDefinitions.aside(for: Support.turn("a happy accident"), after: [], dice: &dice) == nil, "grading needs no draw")

        let hard = SpeedDefinitions.hardWords
        let played = hard.dropLast(SpeedDefinitions.offeredCount).enumerated().map { index, word in
            Support.turn(cue: index == 0 ? SpeedDefinitions.opening : SpeedDefinitions.nextWord, reply: "\(word) | a meaning")
        }
        let next = SpeedDefinitions.offer(.hard, after: played, dice: &dice)
        #expect(hard.suffix(SpeedDefinitions.offeredCount).allSatisfy { next.contains("“\($0)”") }, "the three the chat hasn't had")
    }

    @Test func mostWordsAreMediumAndSomeEasyOrHard() {
        var dice = GameDice(seed: 2)
        var counts: [SpeedDefinitions.Difficulty: Int] = [:]
        for _ in 0..<1_000 { counts[SpeedDefinitions.Difficulty.draw(dice: &dice), default: 0] += 1 }
        #expect((540...660).contains(counts[.medium] ?? 0), "\(counts)")
        #expect((140...260).contains(counts[.easy] ?? 0), "\(counts)")
        #expect((140...260).contains(counts[.hard] ?? 0), "\(counts)")
        #expect(SpeedDefinitions.easyWords.contains("umbrella") && SpeedDefinitions.hardWords.contains("serendipity"))
    }

    @Test func youCanGiveTheWordsForTheModelToDefine() async throws {
        let model = ScriptedModel([
            "Petrichor: the smell of rain on dry earth.",
            "gregarious | fond of company",
            "Definition — lasting a very short time",
            "a strange feeling", "found everywhere"
        ])
        let session = Support.session(model)
        session.startGame(.speedDefinitions)
        await Support.play("a word much too long", in: session)
        #expect(session.nudge == "One word, or a short phrase, for the model to define.")
        await Support.play("Petrichor", in: session)
        #expect(session.turns.first?.cue == SpeedDefinitions.yourGame)
        #expect(model.lastMessages == ["\(SpeedDefinitions.yourGame)\n\nPetrichor"], "no words drawn: they are yours")
        #expect(session.turns.first?.answer == "the smell of rain on dry earth")
        #expect(session.gameState?.choices == [SpeedDefinitions.gotIt, SpeedDefinitions.missedIt])
        #expect(SpeedDefinitions.lines(for: session.turns).map(\.text) == ["Word 1 · Yours", "Petrichor", "the smell of rain on dry earth"])

        session.choose(SpeedDefinitions.gotIt)
        #expect(session.gameState?.phase == .yourMove(placeholder: "Your next word for the model to define…"), "you give every word this game")
        await Support.play("petrichor", in: session)
        #expect(session.nudge == "“petrichor” was played already. Try another.")
        await Support.play("gregarious", in: session)
        #expect(session.turns.last?.answer == "fond of company")
        session.choose(SpeedDefinitions.gotIt)
        await Support.play("ephemeral", in: session)
        #expect(session.turns.last?.answer == "lasting a very short time")
        session.choose(SpeedDefinitions.gotIt)
        await Support.play("ennui", in: session)
        session.choose(SpeedDefinitions.missedIt)
        await Support.play("ubiquitous", in: session)
        session.choose(SpeedDefinitions.gotIt)
        #expect(session.nudge == "Game done: the model got 4 of 5, and missed 1.")
        #expect(session.conversationMarkdown?.hasPrefix("Petrichor\nThe model: the smell of rain on dry earth (The model got it.)") == true)
        session.reset()
        #expect(session.history.first?.title == "Speed Definitions: Petrichor")
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

    @Test func fiveWordsMakeAGame() async throws {
        let model = ScriptedModel([
            Self.serendipity, "8/10 — nails the luck part",
            "gregarious | fond of company", "3/10 — too thin",
            "ephemeral | lasting a very short time",
            "petrichor | the smell of rain on dry earth", "7/10 — close enough",
            "ubiquitous | found everywhere", "10/10 — spot on"
        ])
        let session = Support.session(model)
        session.startGame(.speedDefinitions)
        #expect(session.gameState?.choices == [SpeedDefinitions.randomButton])
        session.send()
        await Support.settle(session)
        #expect(model.requests.first?.systemPrompt == SpeedDefinitions.systemPrompt)
        #expect(session.gameState?.phase == .yourMove(placeholder: "Define “serendipity” in ten words or fewer…"))
        let difficulty = try #require(session.turns.first.flatMap(SpeedDefinitions.Difficulty.init(of:)))
        let heading = "Word 1 · \(difficulty.rawValue.capitalized)"
        #expect(SpeedDefinitions.lines(for: session.turns).map(\.text) == [heading, "serendipity"], "the model’s own definition stays hidden")

        await Support.play("a happy accident", in: session)
        let pick = try #require(session.turns.first?.message)
        #expect(pick.hasPrefix("\(SpeedDefinitions.opening)\n\nPick one of these words, all of "))
        #expect(model.lastMessages == [pick, Self.serendipity, "a happy accident"])
        #expect(SpeedDefinitions.lines(for: session.turns).map(\.text)
            == [heading, "serendipity · finding something good without looking for it", "a happy accident", "8/10 · nails the luck part"])
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
        guard case .over(let outcome, _)? = session.gameState?.phase else {
            Issue.record("five words should end the game")
            return
        }
        #expect(outcome.youWon == true)
        #expect(SpeedDefinitions.opener(after: session.turns, dice: &session.dice) == .ask(SpeedDefinitions.newGame))
        #expect(session.conversationMarkdown?.hasPrefix("serendipity: finding something good without looking for it\nYou: a happy accident (8/10 · nails the luck part)") == true)
    }

    @Test func aMissingGradeSendsTheDefinitionBack() async {
        let model = ScriptedModel([Self.serendipity, "What a lovely try!"])
        let session = Support.session(model)
        session.startGame(.speedDefinitions)
        session.send()
        await Support.settle(session)
        await Support.play("a happy accident", in: session)
        #expect(session.nudge == "The model forgot to grade your definition. Press Return to send it again.")
        #expect(session.draft == "a happy accident")
        #expect(session.isYourMove)
    }
}
