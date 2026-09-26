import Foundation
import Testing
@testable import Meraline

struct GameRulesTests {
    private typealias Support = GameTestSupport

    @Test func everyGameIsReadyForTheMenu() {
        #expect(Game.allCases.count == 6)
        #expect(Set(Game.allCases.map(\.title)).count == Game.allCases.count)
        for game in Game.allCases {
            #expect(!game.summary.isEmpty, "\(game) needs a line for the menu")
            #expect(!game.rules.systemPrompt.isEmpty)
            #expect(!game.rules.invitation.isEmpty)
            guard case .modelMoves = game.rules.state(of: []).phase else {
                Issue.record("\(game) should start with the model’s move")
                continue
            }
        }
    }

    @Test func verdictsAreReadLeniently() {
        #expect(GameText.verdict(of: "OK: spatula") == (true, "spatula"))
        #expect(GameText.verdict(of: "**OK:** spatula") == (true, "spatula"))
        #expect(GameText.verdict(of: "ok\nspatula") == (true, "spatula"))
        #expect(GameText.verdict(of: "NO: a tiger isn’t found in a kitchen") == (false, "a tiger isn’t found in a kitchen"))
        #expect(GameText.verdict(of: "Yes - fork") == (true, "fork"))
        #expect(GameText.verdict(of: "okra") == (nil, "okra"), "a word that starts like a verdict is a word")
        #expect(GameText.verdict(of: "nothing") == (nil, "nothing"))
    }

    @Test func pluralsAreTheSameWord() {
        #expect(GameText.sameWord("spoon", "Spoons"))
        #expect(GameText.sameWord("glass", "glasses"))
        #expect(GameText.sameWord("frying pan", "Frying-pan"))
        #expect(!GameText.sameWord("pan", "plan"))
        #expect(GameText.isGivingUp("Pass."))
        #expect(GameText.isGivingUp("I give up"))
    }

    @Test func aScoreIsFoundInAnyWording() throws {
        let score = try #require(AddAWord.score(in: "Score: 7/10 — a bold claim."))
        #expect(score.score == 7)
        #expect(score.comment == "a bold claim")
        #expect(AddAWord.score(in: "I’d say 4 out of 10")?.score == 4)
        #expect(AddAWord.score(in: "moon.") == nil)
        #expect(AddAWord.score(in: "Score: 12/10") == nil)
    }

    @Test func aModelThatRepeatsTheSentenceGetsItsNewWord() {
        #expect(AddAWord.newWord(in: ["Yesterday", "my", "grandmother"], after: ["Yesterday", "my"]) == "grandmother")
        #expect(AddAWord.newWord(in: ["grandmother"], after: ["Yesterday", "my"]) == "grandmother")
        #expect(AddAWord.newWord(in: ["sang", "loudly"], after: ["Yesterday", "my"]) == "sang")
        #expect(AddAWord.newWord(in: [], after: ["Yesterday"]) == nil)
    }

    @Test func oddOneOutPuzzlesInMostShapes() {
        let expected = OddOneOut.Puzzle(options: ["apple", "hammer", "banana"], answer: "hammer", reason: "not a fruit")
        #expect(OddOneOut.puzzle(from: "apple · hammer · banana | hammer: not a fruit") == expected)
        #expect(OddOneOut.puzzle(from: "1. apple, 2. hammer, 3. banana | The hammer - not a fruit.") == expected)
        #expect(OddOneOut.puzzle(from: "apple, hammer and banana\nhammer: not a fruit") == expected)
        #expect(OddOneOut.puzzle(from: "apple · hammer · banana") == nil, "the answer is missing")
        #expect(OddOneOut.puzzle(from: "apple · hammer · banana | pear: not listed") == nil)
        #expect(OddOneOut.puzzle(from: "apple · banana | hammer: two words") == nil)
        #expect(OddOneOut.choose("2", from: expected.options) == "hammer")
        #expect(OddOneOut.choose("Ham", from: expected.options) == "hammer")
        #expect(OddOneOut.choose("pear", from: expected.options) == nil)
    }

    @Test func fixTheTypoPuzzlesInMostShapes() {
        let expected = FixTheTypo.Puzzle(sentence: "We will meet at the libary after lunch.", typo: "libary", fix: "library")
        #expect(FixTheTypo.puzzle(from: "We will meet at the libary after lunch. | libary → library") == expected)
        #expect(FixTheTypo.puzzle(from: "We will meet at the libary after lunch. | “libary” -> “library”.") == expected)
        #expect(FixTheTypo.puzzle(from: "We will meet at the libary after lunch.\nlibary → library") == expected)
        #expect(FixTheTypo.puzzle(from: "We will meet at the library after lunch. | libary → library") == nil, "the typo isn’t in the sentence")
        #expect(FixTheTypo.puzzle(from: "We will meet at the libary after lunch.") == nil)
    }

    @Test func categoryNamesLoseTheirDecoration() {
        #expect(Categories.categoryName("Category: **Kitchen**.") == "Kitchen")
        #expect(Categories.categoryName("“Things at the beach”") == "Things at the beach")
    }

    @Test func wordFootballChecksTheChainBeforeAsking() {
        let turns = [Support.turn(cue: WordFootball.opening, reply: "banana")]
        #expect(WordFootball.play("egg", in: turns, insisting: false) == .reject("“egg” starts with “E”. You need a word starting with “A”."))
        #expect(WordFootball.play("banana", in: turns, insisting: false) == .reject("“banana” starts with “B”. You need a word starting with “A”."))
        #expect(WordFootball.play("apple pie", in: turns, insisting: false) == .reject("One word at a time."))
        #expect(WordFootball.play("Apple!", in: turns, insisting: false) == .ask("apple"))
        #expect(WordFootball.play("pass", in: turns, insisting: false) == .record("pass", outcome: GameOutcome(text: "You passed, so the model takes this match.", youWon: false)))
    }
}

@MainActor
struct GamePlayTests {
    private typealias Support = GameTestSupport

    @Test func categoriesJudgesYourWordsAndPlaysItsOwn() async {
        let model = ScriptedModel(["Kitchen", "OK: spatula", "NO: tigers don’t live in kitchens", "Category: Animals"])
        let session = Support.session(model)
        session.startGame(.categories)
        await Support.settle(session)
        #expect(session.gameState?.status == "Kitchen · 0 of 12")
        #expect(model.requests.first?.systemPrompt == Categories.systemPrompt)

        await Support.play("spoon", in: session)
        #expect(session.gameState?.status == "Kitchen · 2 of 12")
        #expect(Categories.lines(for: session.turns).map(\.text) == ["Kitchen", "spoon · spatula"])
        #expect(model.lastMessages == [Categories.opening, "Kitchen", "spoon"])

        await Support.play("Spatulas", in: session)
        #expect(model.requests.count == 2, "a repeat is caught before asking")
        #expect(session.nudge == "“spatula” is taken already. Name something else.")

        await Support.play("tiger", in: session)
        #expect(session.nudge == "Not quite: Tigers don’t live in kitchens.")
        #expect(session.draft == "tiger", "a word the model turns down comes back to you")
        #expect(session.gameState?.status == "Kitchen · 2 of 12")

        await Support.play("pass", in: session)
        #expect(session.nudge == "You passed, so the model takes this round. Press Return for a new category.")
        session.send()
        await Support.settle(session)
        #expect(session.turns.last?.cue == Categories.nextCategory)
        #expect(session.gameState?.status == "Animals · 0 of 12")
    }

    @Test func categoriesEndsWhenTheModelRepeatsOrPasses() {
        let kitchen = [Support.turn(cue: Categories.opening, reply: "Kitchen"), Support.turn("spoon", reply: "OK: spoons")]
        #expect(Categories.review(kitchen).ending == GameOutcome(text: "Foul: “spoons” was named already. You win!", youWon: true))
        let passed = [Support.turn(cue: Categories.opening, reply: "Kitchen"), Support.turn("spoon", reply: "OK: PASS")]
        #expect(Categories.review(passed).ending?.youWon == true)
        let full = [Support.turn(cue: Categories.opening, reply: "Kitchen")] + (1...6).map { Support.turn("mine \($0)", reply: "OK: theirs \($0)") }
        #expect(Categories.review(full).ending?.youWon == nil, "six each is a draw")
    }

    @Test func wordFootballCallsTheModelsFouls() async {
        let model = ScriptedModel(["Banana.", "OK: elephant", "NO: that isn’t a word", "OK: salmon"])
        let session = Support.session(model)
        session.startGame(.wordFootball)
        await Support.settle(session)
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “A”…"))

        await Support.play("apple", in: session)
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “T”…"))
        #expect(session.gameState?.status == "2 of 16 words")

        await Support.play("tzzq", in: session)
        #expect(session.nudge == "The ref says no: That isn’t a word.")
        #expect(session.draft == "tzzq")

        await Support.play("tiger", in: session)
        #expect(session.nudge == "Foul! “salmon” doesn’t start with “R”. You win! Press Return for a new match.")
        guard case .over = session.gameState?.phase else {
            Issue.record("the foul should end the match")
            return
        }
        #expect(WordFootball.lines(for: session.turns).map(\.text).first == "banana → apple → elephant → tiger → salmon")
    }

    @Test func addAWordBuildsAStoryAndScoresEachSentence() async {
        let model = ScriptedModel(["Yesterday", "grandmother", "Score: 7/10 — lively, if unlikely", "Then"])
        let session = Support.session(model)
        session.startGame(.addAWord)
        await Support.settle(session)
        #expect(session.gameState?.status == "Sentence 1 · 1 word")

        await Support.play("my grandmother", in: session)
        #expect(session.nudge == "Just one word at a time. “my” first?")
        #expect(model.requests.count == 1)

        await Support.play("my", in: session)
        await Support.play("danced.", in: session)
        #expect(session.gameState?.status == "Sentence 1 · 7/10")
        #expect(session.nudge?.hasPrefix("Sentence done: 7 out of 10") == true)
        #expect(AddAWord.lines(for: session.turns).map(\.text) == ["Yesterday my grandmother danced.", "7/10 · lively, if unlikely"])

        session.send()
        await Support.settle(session)
        #expect(model.lastMessages.first == AddAWord.opening)
        #expect(model.lastMessages.last == AddAWord.nextSentence, "the next sentence carries the story so far")
        #expect(session.gameState?.status == "Sentence 2 · 1 word")
        #expect(session.conversationMarkdown == "Yesterday my grandmother danced. (7/10)\nThen")
    }

    @Test func addAWordAsksAgainWhenTheScoreIsMissing() async {
        let model = ScriptedModel(["Yesterday", "grandmother"])
        let session = Support.session(model)
        session.startGame(.addAWord)
        await Support.settle(session)
        await Support.play("my", in: session)
        model.replies = ["What a sentence!"]
        await Support.play("danced.", in: session)
        #expect(session.nudge == "The model forgot to score the sentence. Press Return to ask again.")
        #expect(session.draft == "danced.")
    }

    @Test func oddOneOutAlternatesAndKeepsScore() async {
        let model = ScriptedModel([
            "apple · hammer · banana | hammer: not a fruit",
            "piano: not a fruit",
            "red · blue · seven | seven: not a color"
        ])
        let session = Support.session(model)
        session.startGame(.oddOneOut)
        await Support.settle(session)
        #expect(session.gameState?.choices == ["apple", "hammer", "banana"])
        #expect(OddOneOut.lines(for: session.turns).map(\.text) == ["Round 1 · the model’s three"], "the answer stays hidden")

        session.choose("hammer")
        #expect(session.turns.last?.outcome == GameOutcome(text: "Right, “hammer”: not a fruit.", youWon: true))
        #expect(session.gameState?.phase == .yourMove(placeholder: "Your three words, one that doesn’t belong…"))
        #expect(model.requests.count == 1, "your round needs no model move yet")

        await Support.play("pear plum", in: session)
        #expect(session.nudge == "Three different words, one that doesn’t belong, separated by commas.")
        await Support.play("pear, plum, piano", in: session)
        #expect(model.lastMessages.last == "pear, plum, piano")
        #expect(session.gameState?.choices == [OddOneOut.gotIt, OddOneOut.missedIt])

        session.choose(OddOneOut.gotIt)
        #expect(model.requests.count == 3, "the model sets the next puzzle at once")
        await Support.settle(session)
        #expect(session.gameState?.status == "Round 3 of 6 · You 1, Model 1")
        #expect(session.gameState?.choices == ["red", "blue", "seven"])
    }

    @Test func oddOneOutFinishesAfterSixRounds() {
        let puzzle = "apple · hammer · banana | hammer: not a fruit"
        var turns: [ChatSession.Turn] = []
        for round in 0..<6 {
            if round.isMultiple(of: 2) {
                turns.append(Support.turn(cue: round == 0 ? OddOneOut.opening : OddOneOut.nextPuzzle, reply: puzzle, outcome: GameOutcome(text: "Right", youWon: true)))
            } else {
                turns.append(Support.turn("pear, plum, piano", reply: "piano: not a fruit", outcome: GameOutcome(text: "Got it", youWon: false)))
            }
        }
        guard case .over(let summary, let rematch) = OddOneOut.state(of: turns).phase else {
            Issue.record("six rounds should end the game")
            return
        }
        #expect(summary.hasPrefix("Game done: a draw, 3 all."))
        #expect(rematch.cue == OddOneOut.newGame)
    }

    @Test func fixTheTypoJudgesYourFixOnThisMac() async {
        let model = ScriptedModel([
            "We will meet at the libary after lunch. | libary → library",
            "The cat slept on the warm windowsill all day.",
            "Please recieve this gift with our thanks. | recieve → receive"
        ])
        let session = Support.session(model)
        session.startGame(.fixTheTypo)
        await Support.settle(session)
        #expect(FixTheTypo.lines(for: session.turns).map(\.text) == ["We will meet at the libary after lunch."])
        #expect(model.requests.first?.systemPrompt == FixTheTypo.systemPrompt)

        await Support.play("lunch", in: session)
        #expect(session.nudge == "Not quite. Look again, or type pass to see it.")
        await Support.play("libary", in: session)
        #expect(session.nudge == "Found it! Now type it spelled right.")
        await Support.play("Library", in: session)
        #expect(session.turns.first?.outcome?.youWon == true)
        #expect(FixTheTypo.lines(for: session.turns).first?.pieces.filter(\.isMarked).map(\.text) == [" libary"])

        #expect(session.nudge == "The model’s sentence came out garbled. Press Return for another.", "the next sentence came back without its typo")
        #expect(session.turns.count == 1)
        session.send()
        await Support.settle(session)
        #expect(session.gameState?.status == "Sentence 2 of 5 · 1 fixed")
        await Support.play("pass", in: session)
        #expect(session.turns.last?.outcome == GameOutcome(text: "It was “recieve”, spelled “receive”.", youWon: false))
    }

    @Test func aGameIgnoresTheSettingsPromptAndTheChatDoesNot() {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences) { ScriptedModel().stream($0) }
        for game in Game.allCases {
            session.startGame(game)
            #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt == game.rules.systemPrompt)
        }
        session.reset()
        #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt == preferences.systemPrompt)
    }

    @Test func stoppingTheModelsMoveTakesItBack() async {
        let session = Support.session(ScriptedModel())
        session.startGame(.fixTheTypo)
        session.stop()
        await Support.settle(session)
        #expect(session.turns.isEmpty)
        #expect(session.canSend, "Return asks again")
    }
}
