import Foundation
import Testing
@testable import Meraline

struct GameRulesTests {
    private typealias Support = GameTestSupport

    @Test func everyGameIsReadyForTheMenu() {
        #expect(Game.allCases.count == 8)
        #expect(Set(Game.allCases.map(\.title)).count == Game.allCases.count)
        for game in Game.allCases {
            #expect(!game.summary.isEmpty, "\(game) needs a line for the menu")
            #expect(!game.rules.systemPrompt.isEmpty)
            #expect(!game.rules.invitation.isEmpty)
            switch game.rules.state(of: []).phase {
            case .modelMoves, .opening: break
            default: Issue.record("\(game) should start with the model’s move, or wait for someone to open")
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
        let score = try #require(GameText.score(in: "Score: 7/10 — a bold claim."))
        #expect(score.score == 7)
        #expect(score.comment == "a bold claim")
        #expect(GameText.score(in: "I’d say 4 out of 10")?.score == 4)
        #expect(GameText.score(in: "moon.") == nil)
        #expect(GameText.score(in: "Score: 12/10") == nil)
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

    @Test func categoriesDrawsACategoryTheChatHasntPlayed() throws {
        #expect(Set(Categories.categories.map(GameText.key)).count == Categories.categories.count, "no category twice")
        var dice = GameDice(seed: 5)
        var first = Support.turn(cue: Categories.randomCategory)
        first.aside = try #require(Categories.aside(for: first, after: [], dice: &dice))
        let category = try #require(Categories.category(of: first))
        #expect(Categories.categories.contains(category))
        #expect(first.aside == "This round’s category: “\(category)”.")
        #expect(Categories.aside(for: Support.turn("spoon"), after: [first], dice: &dice) == nil, "only a new round draws")

        let played = Categories.categories.dropLast().map { category in
            [Support.turn(category, cue: Categories.yourCategory, reply: "OK: one"), Support.turn("pass", outcome: GameOutcome(text: "Passed", youWon: false))]
        }.joined()
        let next = try #require(Categories.aside(for: Support.turn(cue: Categories.randomCategory), after: Array(played), dice: &dice))
        #expect(next == "This round’s category: “\(try #require(Categories.categories.last))”.", "the one left unplayed")
    }

    @Test func oddOneOutGivesEachOfTheModelsPuzzlesAFreshTheme() throws {
        #expect(Set(OddOneOut.themes).count == OddOneOut.themes.count, "no theme twice")
        var dice = GameDice(seed: 9)
        for cue in [OddOneOut.opening, OddOneOut.nextPuzzle, OddOneOut.newGame] {
            let aside = try #require(OddOneOut.aside(for: Support.turn(cue: cue), after: [], dice: &dice))
            #expect(OddOneOut.themes.contains { aside.hasPrefix("This puzzle’s theme: \($0). ") })
            #expect(OddOneOut.links.contains { aside.hasSuffix(" Link the two that belong by \($0).") })
        }
        #expect(OddOneOut.aside(for: Support.turn("pear, plum, piano"), after: [], dice: &dice) == nil, "the model picks yours without a draw")

        var turns: [ChatSession.Turn] = []
        for theme in OddOneOut.themes.dropLast() {
            var turn = Support.turn(cue: OddOneOut.nextPuzzle, reply: "apple · hammer · banana | hammer: not a fruit")
            turn.aside = "This puzzle’s theme: \(theme). Link the two that belong by what they are."
            turns.append(turn)
        }
        let last = try #require(OddOneOut.themes.last)
        let aside = try #require(OddOneOut.aside(for: Support.turn(cue: OddOneOut.nextPuzzle), after: turns, dice: &dice))
        #expect(aside.hasPrefix("This puzzle’s theme: \(last). "), "the one theme the chat hasn't had")
    }

    @Test func wordFootballDrawsTheKickoffsLetterAndAKindOfWord() throws {
        var letters: Set<String> = []
        for seed: UInt64 in 0..<40 {
            var dice = GameDice(seed: seed)
            let cue = Support.turn(cue: seed.isMultiple(of: 2) ? WordFootball.opening : WordFootball.rematchCue)
            let kickoff = try #require(WordFootball.aside(for: cue, after: [], dice: &dice))
            let letter = try #require(kickoff.firstMatch(of: #/starts with “([A-Z])”, (.+) if one comes to mind\./#))
            #expect(WordFootball.kickoffLetters.contains(Character(letter.1.lowercased())))
            #expect(WordFootball.kinds.contains(String(letter.2)))
            letters.insert(String(letter.1))
        }
        #expect(letters.count >= 10, "a different letter from match to match")

        var dice = GameDice(seed: 1)
        let turns = [Support.turn(cue: WordFootball.opening, reply: "banana")]
        let answer = try #require(WordFootball.aside(for: Support.turn("apple"), after: turns, dice: &dice))
        #expect(answer.hasPrefix("For your own word, try "))
        #expect(WordFootball.kinds.contains { answer == "For your own word, try \($0) if one fits." })
    }

    @Test func aTurnSendsItsCueQuestionAndAsideInThatOrder() {
        var opening = ChatSession.Turn(question: "Once a cat", images: [], cue: "The user opens the round.")
        opening.aside = "End on a rhyme."
        #expect(opening.message == "The user opens the round.\n\nOnce a cat\n\nEnd on a rhyme.")
        #expect(ChatSession.Turn(question: "", images: [], cue: "Open the round.").message == "Open the round.")
        #expect(ChatSession.Turn(question: "apple", images: []).message == "apple")
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

    @Test func categoriesStartsFromYourCategoryAndTheModelNamesFirst() async throws {
        let model = ScriptedModel(["NO: that’s a single thing, not a category", "OK: spatula", "OK: fork", "NO: tigers don’t live in kitchens", "OK: pasta"])
        let session = Support.session(model)
        session.startGame(.categories)
        #expect(session.gameState?.isOpening == true)
        #expect(session.gameState?.choices == [Categories.randomButton])
        #expect(model.requests.isEmpty)

        await Support.play("Spoon", in: session)
        #expect(session.nudge == "Not that one: That’s a single thing, not a category.")
        #expect(session.draft == "Spoon", "a category the model won’t play comes back")
        #expect(session.gameState?.isOpening == true)

        await Support.play("Category: **Kitchen**", in: session)
        #expect(session.turns.first?.cue == Categories.yourCategory)
        #expect(session.gameState?.status == "Kitchen · 1 of 12", "the model named the first thing")
        #expect(model.requests.first?.systemPrompt == Categories.systemPrompt)
        #expect(model.lastMessages == ["\(Categories.yourCategory)\n\nKitchen"])

        await Support.play("spoon", in: session)
        #expect(session.gameState?.status == "Kitchen · 3 of 12")
        #expect(Categories.lines(for: session.turns).map(\.text) == ["Kitchen", "spatula · spoon · fork"])
        #expect(model.lastMessages == ["\(Categories.yourCategory)\n\nKitchen", "OK: spatula", "spoon"], "the model names things without a draw")

        await Support.play("Spatulas", in: session)
        #expect(model.requests.count == 3, "a repeat is caught before asking")
        #expect(session.nudge == "“spatula” is taken already. Name something else.")

        await Support.play("tiger", in: session)
        #expect(session.nudge == "Not quite: Tigers don’t live in kitchens.")
        #expect(session.draft == "tiger", "a word the model turns down comes back to you")
        #expect(session.gameState?.status == "Kitchen · 3 of 12")

        await Support.play("pass", in: session)
        #expect(session.nudge == "You passed, so the model takes this round.")
        session.dice = GameDice(seed: 8)
        session.send()
        await Support.settle(session)
        let drawn = try #require(session.turns.last.flatMap(Categories.category(of:)))
        #expect(session.turns.last?.cue == Categories.randomCategory, "Return with nothing typed draws a category")
        #expect(drawn != "Kitchen")
        #expect(session.gameState?.status == "\(drawn) · 1 of 12")
        #expect(session.history.isEmpty)
        session.reset()
        #expect(session.history.first?.title == "Categories: Kitchen")
    }

    @Test func categoriesEndsWhenTheModelRepeatsOrPasses() {
        let kitchen = Support.turn("Kitchen", cue: Categories.yourCategory, reply: "OK: spoon")
        #expect(Categories.review([kitchen, Support.turn("fork", reply: "OK: spoons")]).ending == GameOutcome(text: "Foul: “spoons” was named already. You win!", youWon: true))
        #expect(Categories.review([kitchen, Support.turn("fork", reply: "OK: PASS")]).ending?.youWon == true)
        let five = (1...5).map { Support.turn("mine \($0)", reply: "OK: theirs \($0)") }
        let last = Support.turn("mine 6")
        #expect(Categories.review([kitchen] + five + [last]).named.count == Categories.limit)
        var dice = GameDice(seed: 1)
        #expect(Categories.aside(for: last, after: [kitchen] + five, dice: &dice) == Categories.lastOne)
        #expect(Categories.aside(for: five[0], after: [kitchen], dice: &dice) == nil)
        #expect(Categories.judge("OK", in: [kitchen] + five + [ChatSession.Turn(question: "mine 6", images: [])]) == .accept("OK"))
        let full = [kitchen] + five + [Support.turn("mine 6", reply: "OK: one more anyway")]
        #expect(Categories.review(full).ending?.youWon == nil, "six each is a draw")
        #expect(Categories.review(full).named.count == Categories.limit, "nothing after your last one counts")
    }

    @Test func wordFootballCallsTheModelsFouls() async throws {
        let model = ScriptedModel(["Banana.", "OK: elephant", "NO: that isn’t a word", "OK: salmon"])
        let session = Support.session(model)
        session.startGame(.wordFootball)
        await Support.settle(session)
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “A”…"))
        let kickoff = try #require(session.turns.first?.message)
        #expect(kickoff.hasPrefix("\(WordFootball.opening)\n\nKick off with a word that starts with “"))

        await Support.play("apple", in: session)
        #expect(model.lastMessages == [kickoff, "banana", try #require(session.turns.last?.message)])
        #expect(session.turns.last?.message.hasPrefix("apple\n\nFor your own word, try ") == true)
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “T”…"))
        #expect(session.gameState?.status == "2 of 16 words")

        await Support.play("tzzq", in: session)
        #expect(session.nudge == "The ref says no: That isn’t a word.")
        #expect(session.draft == "tzzq")

        await Support.play("tiger", in: session)
        #expect(session.nudge == "Foul! “salmon” doesn’t start with “R”. You win!")
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
        #expect(model.lastMessages.first?.hasPrefix("\(OddOneOut.opening)\n\nThis puzzle’s theme: ") == true)
        #expect(model.lastMessages.first == session.turns.first?.message)
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
        guard case .over(let outcome, _) = OddOneOut.state(of: turns).phase else {
            Issue.record("six rounds should end the game")
            return
        }
        #expect(outcome == GameOutcome(text: "Game done: a draw, 3 all.", youWon: nil))
        var dice = GameDice(seed: 1)
        #expect(OddOneOut.opener(after: turns, dice: &dice) == .ask(OddOneOut.newGame))
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

    @Test func aGameSendsItsOwnPromptAndTheChatSendsItsModes() {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences) { ScriptedModel().stream($0) }
        for game in Game.allCases {
            session.startGame(game)
            #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt == game.rules.systemPrompt)
        }
        preferences[prompt: .game(.oddOneOut)] = "Odd one out, in Czech."
        session.startGame(.oddOneOut)
        #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt == "Odd one out, in Czech.")
        session.reset()
        preferences[prompt: .chat(.agent)] = "Agents only."
        #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt == SystemPrompt.llm)
        #expect(session.makeRequest(asking: "Hi", images: [], of: .claudeCode).systemPrompt == "Agents only.")
        session.reset() // drops the workspace the agent's request made
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
