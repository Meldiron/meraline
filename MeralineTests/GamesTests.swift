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
        #expect(FixTheTypo.correction(in: "The word “tomorow” → tomorrow.")?.typo == "tomorow")
        #expect(FixTheTypo.correction(in: "Typo: hapy -> happy")?.fix == "happy")
        #expect(FixTheTypo.correction(in: "Nothing to fix") == nil)
    }

    @Test func categoryNamesLoseTheirDecoration() {
        #expect(Categories.categoryName("Category: **Kitchen**.") == "Kitchen")
        #expect(Categories.categoryName("“Things at the beach”") == "Things at the beach")
    }

    @Test func categoriesDrawsACategoryTheChatHasntPlayed() throws {
        #expect(Set(Categories.categories.map(GameText.key)).count == Categories.categories.count, "no category twice")
        var dice = GameDice(seed: 5)
        var first = Support.turn(cue: Categories.randomCategory)
        first.aside = try #require(Categories.aside(for: first, after: [], in: .english, dice: &dice))
        let category = try #require(Categories.category(of: first))
        #expect(Categories.categories.contains(category))
        #expect(first.aside == "This round’s category: “\(category)”.")
        #expect(Categories.aside(for: Support.turn("spoon"), after: [first], in: .english, dice: &dice) == nil, "only a new round draws")

        let played = Categories.categories.dropLast().map { category in
            [Support.turn(category, cue: Categories.yourCategory, reply: "OK: one"), Support.turn("pass", outcome: GameOutcome(text: "Passed", youWon: false))]
        }.joined()
        let next = try #require(Categories.aside(for: Support.turn(cue: Categories.randomCategory), after: Array(played), in: .english, dice: &dice))
        #expect(next == "This round’s category: “\(try #require(Categories.categories.last))”.", "the one left unplayed")
    }

    @Test func oddOneOutGivesEachOfTheModelsPuzzlesAFreshTheme() throws {
        #expect(Set(OddOneOut.themes).count == OddOneOut.themes.count, "no theme twice")
        var dice = GameDice(seed: 9)
        for cue in [OddOneOut.opening, OddOneOut.nextPuzzle, OddOneOut.newGame] {
            let aside = try #require(OddOneOut.aside(for: Support.turn(cue: cue), after: [], in: .english, dice: &dice))
            #expect(OddOneOut.themes.contains { aside.hasPrefix("This puzzle’s theme: \($0). ") })
            #expect(OddOneOut.links.contains { aside.hasSuffix(" Link the two that belong by \($0).") })
        }
        #expect(OddOneOut.aside(for: Support.turn("pear, plum, piano"), after: [], in: .english, dice: &dice) == nil, "the model picks yours without a draw")

        var turns: [ChatSession.Turn] = []
        for theme in OddOneOut.themes.dropLast() {
            var turn = Support.turn(cue: OddOneOut.nextPuzzle, reply: "apple · hammer · banana | hammer: not a fruit")
            turn.aside = "This puzzle’s theme: \(theme). Link the two that belong by what they are."
            turns.append(turn)
        }
        let last = try #require(OddOneOut.themes.last)
        let aside = try #require(OddOneOut.aside(for: Support.turn(cue: OddOneOut.nextPuzzle), after: turns, in: .english, dice: &dice))
        #expect(aside.hasPrefix("This puzzle’s theme: \(last). "), "the one theme the chat hasn't had")
    }

    @Test func wordFootballKicksOffFromAFreshWordAndNudgesTheModelsWords() throws {
        #expect(Set(WordFootball.kickoffs).count == WordFootball.kickoffs.count, "no kickoff twice")
        #expect(WordFootball.kickoffs.allSatisfy { $0 == WordFootball.cleanWord($0) && $0.count >= 2 })
        var dice = GameDice(seed: 3)
        guard case .drawn(let cue, let word) = WordFootball.opener(after: [], in: .english, dice: &dice) else {
            Issue.record("the kickoff is drawn on this Mac")
            return
        }
        #expect(cue == WordFootball.opening)
        #expect(WordFootball.kickoffs.contains(word))
        let played = WordFootball.kickoffs.dropLast().map { Support.turn(cue: WordFootball.rematchCue, reply: $0) }
        #expect(WordFootball.opener(after: played, in: .english, dice: &dice) == .drawn(cue: WordFootball.rematchCue, move: try #require(WordFootball.kickoffs.last)))

        let turns = [Support.turn(cue: WordFootball.opening, reply: "banana")]
        let answer = try #require(WordFootball.aside(for: Support.turn("apple"), after: turns, in: .english, dice: &dice))
        #expect(WordFootball.kinds.contains { answer == "For your own word, try \($0) if one fits." })
        #expect(WordFootball.aside(for: Support.turn(cue: WordFootball.opening), after: [], in: .english, dice: &dice)?.hasPrefix("Kick off with a common word, ") == true, "for a model that kicks off")
        #expect(WordFootball.open(with: "Apple!", after: []) == .open("apple", cue: WordFootball.yourKickoff))
        #expect(WordFootball.open(with: "pass", after: []) == .reject("Kick off with a word first."))
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
        #expect(session.gameState?.opening?.button == Categories.randomButton)
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
        #expect(Categories.aside(for: last, after: [kitchen] + five, in: .english, dice: &dice) == Categories.lastOne)
        #expect(Categories.aside(for: five[0], after: [kitchen], in: .english, dice: &dice) == nil)
        #expect(Categories.judge("OK", in: [kitchen] + five + [ChatSession.Turn(question: "mine 6", images: [])]) == .accept("OK"))
        let full = [kitchen] + five + [Support.turn("mine 6", reply: "OK: one more anyway")]
        #expect(Categories.review(full).ending?.youWon == nil, "six each is a draw")
        #expect(Categories.review(full).named.count == Categories.limit, "nothing after your last one counts")
    }

    @Test func wordFootballCallsTheModelsFouls() async throws {
        let model = ScriptedModel(["OK: apple", "NO: that isn’t a word", "OK: salmon"])
        let session = Support.session(model)
        session.startGame(.wordFootball)
        #expect(session.gameState?.opening?.button == WordFootball.randomButton)
        await Support.play("Banana", in: session)
        let kickoff = try #require(session.turns.first)
        #expect(kickoff.cue == WordFootball.yourKickoff)
        #expect(kickoff.message.hasPrefix("\(WordFootball.yourKickoff)\n\nbanana\n\nFor your own word, try "))
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “E”…"))
        #expect(session.gameState?.status == "1 of 16 words")

        await Support.play("ezzq", in: session)
        #expect(session.nudge == "The ref says no: That isn’t a word.")
        #expect(session.draft == "ezzq")

        await Support.play("egg", in: session)
        #expect(model.lastMessages.prefix(2) == [kickoff.message, "OK: apple"])
        #expect(session.nudge == "Foul! “salmon” doesn’t start with “G”. You win!")
        guard case .over = session.gameState?.phase else {
            Issue.record("the foul should end the match")
            return
        }
        #expect(WordFootball.lines(for: session.turns).map(\.text).first == "banana → apple → egg → salmon")
        session.reset()
        #expect(session.history.first?.title == "Word Football: banana")
    }

    @Test func wordFootballCanKickOffFromARandomWord() async throws {
        let model = ScriptedModel(["OK: salmon"])
        let session = Support.session(model)
        session.startGame(.wordFootball)
        session.send()
        #expect(model.requests.isEmpty, "the kickoff is drawn on this Mac")
        let kickoff = try #require(session.turns.first?.answer)
        #expect(WordFootball.kickoffs.contains(kickoff))
        let letter = try #require(WordFootball.lastLetter(of: kickoff)).uppercased()
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “\(letter)”…"))
        #expect(WordFootball.lines(for: session.turns).first?.pieces.first?.voice == .model)
    }

    @Test func addAWordBuildsAStoryFromYourFirstWordAndScoresEachSentence() async {
        let model = ScriptedModel(["my", "danced.\nScore: 7/10 — lively, if unlikely", "nobody"])
        let session = Support.session(model)
        session.startGame(.addAWord)
        #expect(session.gameState?.isOpening == true)
        #expect(session.gameState?.opening?.button == AddAWord.randomButton)

        await Support.play("Yesterday grandma", in: session)
        #expect(session.nudge == "Just one word at a time. “Yesterday” first?")
        #expect(model.requests.isEmpty)
        await Support.play("Yesterday", in: session)
        #expect(session.turns.first?.cue == AddAWord.yourOpening)
        #expect(model.lastMessages == ["\(AddAWord.yourOpening)\n\nYesterday"])
        #expect(session.gameState?.status == "Sentence 1 · 2 words")

        await Support.play("grandmother", in: session)
        #expect(session.gameState?.status == "Sentence 1 · 7/10")
        #expect(session.nudge?.hasPrefix("Sentence done: 7 out of 10") == true)
        #expect(AddAWord.lines(for: session.turns).map(\.text) == ["Yesterday my grandmother danced.", "7/10 · lively, if unlikely"])

        await Support.play("Then", in: session)
        #expect(session.turns.last?.cue == AddAWord.yourNextSentence, "a word typed once a sentence is done starts the next")
        #expect(model.lastMessages.last == "\(AddAWord.yourNextSentence)\n\nThen\n\n\(AddAWord.storySoFar)Yesterday my grandmother danced.", "the next sentence brings the story so far, written out")
        #expect(session.gameState?.status == "Sentence 2 · 2 words")
        #expect(session.conversationMarkdown == "Yesterday my grandmother danced. (7/10)\nThen nobody")
        #expect(AddAWord.lines(for: session.turns).map(\.text).last == "Then nobody", "the story so far never shows")

        await Support.play("smiled", in: session)
        #expect(model.lastMessages.last == "smiled", "once a sentence has it, its next words go alone")
        #expect(model.lastMessages.filter { $0.contains(AddAWord.storySoFar) }.count == 1, "and the model reads it once, where it came")
    }

    @Test func addAWordGivesEachLaterSentenceTheStorySoFar() throws {
        var dice = GameDice(seed: 1)
        let first = [
            Support.turn("Yesterday", cue: AddAWord.yourOpening, reply: "my"),
            Support.turn("grandmother", reply: "danced.\nScore: 7/10 — lively")
        ]
        #expect(AddAWord.aside(for: Support.turn("Yesterday", cue: AddAWord.yourOpening), after: [], in: .english, dice: &dice) == nil, "the first sentence has no story yet")
        #expect(AddAWord.aside(for: Support.turn("grandmother"), after: [first[0]], in: .english, dice: &dice) == nil)

        let story = "\(AddAWord.storySoFar)Yesterday my grandmother danced."
        #expect(AddAWord.aside(for: Support.turn("Then", cue: AddAWord.yourNextSentence), after: first, in: .english, dice: &dice) == story)
        #expect(AddAWord.aside(for: Support.turn(cue: AddAWord.nextSentence), after: first, in: .czech, dice: &dice) == story, "the model asked to start it")

        let drawn = first + [Support.turn(cue: AddAWord.nextSentence, reply: "Meanwhile")]
        #expect(AddAWord.aside(for: Support.turn("the"), after: drawn, in: .english, dice: &dice) == story, "after a drawn word, with your first word to the model")

        var second = first + [Support.turn("Then", cue: AddAWord.yourNextSentence, reply: "nobody")]
        second[second.count - 1].aside = story
        #expect(AddAWord.aside(for: Support.turn("smiled"), after: second, in: .english, dice: &dice) == nil, "once a sentence")

        second.append(Support.turn("smiled", reply: "again.\nScore: 6/10 — tidy"))
        let third = try #require(AddAWord.aside(for: Support.turn("Later", cue: AddAWord.yourNextSentence), after: second, in: .english, dice: &dice))
        #expect(third == "\(AddAWord.storySoFar)Yesterday my grandmother danced. Then nobody smiled again.", "every finished sentence, in order")
        #expect(AddAWord.systemPrompt.contains("the story so far comes with the sentence's first message"))
        #expect(AddAWord.systemPrompt.contains("10 makes perfect sense in the story so far"))
    }

    @Test func addAWordCanStartFromARandomWord() async throws {
        let model = ScriptedModel(["grandmother"])
        let session = Support.session(model)
        session.dice = GameDice(seed: 6)
        session.startGame(.addAWord)
        session.choose(AddAWord.randomButton)
        #expect(model.requests.isEmpty, "the word is drawn on this Mac")
        let first = try #require(session.turns.first)
        #expect(first.cue == AddAWord.opening)
        #expect(AddAWord.starters.contains(first.answer))
        #expect(session.isYourMove, "your word comes next")
        #expect(AddAWord.lines(for: session.turns).first?.pieces.first?.voice == .model)
        await Support.play("my", in: session)
        #expect(model.lastMessages == [AddAWord.opening, first.answer, "my"], "the model reads the drawn word as its own")

        var dice = GameDice(seed: 1)
        let used = AddAWord.starters.dropLast().map { Support.turn(cue: AddAWord.nextSentence, reply: $0) }
        #expect(AddAWord.opener(after: used, in: .english, dice: &dice) == .drawn(cue: AddAWord.nextSentence, move: try #require(AddAWord.starters.last)), "a word no sentence has started with")
    }

    @Test func addAWordAsksAgainWhenTheScoreIsMissing() async {
        let model = ScriptedModel(["grandmother", "What a sentence!"])
        let session = Support.session(model)
        session.startGame(.addAWord)
        session.send()
        await Support.play("my", in: session)
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
        #expect(session.gameState?.opening?.button == OddOneOut.randomButton)
        session.choose(OddOneOut.randomButton)
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

    @Test func oddOneOutCanStartWithYourPuzzle() async throws {
        let model = ScriptedModel(["piano: not a fruit", "red · blue · seven | seven: not a color", "cello: not a fruit"])
        let session = Support.session(model)
        session.startGame(.oddOneOut)
        await Support.play("pear plum", in: session)
        #expect(session.nudge == "Three different words, one that doesn’t belong, separated by commas.")
        #expect(model.requests.isEmpty)
        await Support.play("pear, plum, piano", in: session)
        #expect(session.turns.first?.cue == OddOneOut.yourGame)
        #expect(model.lastMessages == ["\(OddOneOut.yourGame)\n\npear, plum, piano"], "no theme: the puzzle is yours")
        #expect(session.gameState?.choices == [OddOneOut.gotIt, OddOneOut.missedIt])
        #expect(OddOneOut.lines(for: session.turns).map(\.text) == ["Round 1 · your three", "pear · plum · piano", "The model picks piano: not a fruit"])

        session.choose(OddOneOut.gotIt)
        #expect(model.requests.count == 2, "the model sets round 2 at once")
        await Support.settle(session)
        #expect(session.gameState?.choices == ["red", "blue", "seven"])
        session.choose("seven")
        #expect(session.gameState?.phase == .yourMove(placeholder: "Your three words, one that doesn’t belong…"), "and you set round 3")
        #expect(session.gameState?.status == "Round 3 of 6 · You 1, Model 1")
        await Support.play("apple, pear, cello", in: session)
        #expect(session.turns.last?.cue == nil)
        #expect(session.gameState?.choices == [OddOneOut.gotIt, OddOneOut.missedIt])
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
        #expect(OddOneOut.opener(after: turns, in: .english, dice: &dice) == .ask(OddOneOut.newGame))
    }

    @Test func fixTheTypoJudgesYourFixOnThisMac() async {
        let model = ScriptedModel([
            "We will meet at the libary after lunch. | libary → library",
            "The cat slept on the warm windowsill all day.",
            "Please recieve this gift with our thanks. | recieve → receive"
        ])
        let session = Support.session(model)
        session.startGame(.fixTheTypo)
        #expect(session.gameState?.opening?.button == FixTheTypo.randomButton)
        session.send()
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
        #expect(model.requests.count == 1, "the next sentence waits for you to choose")
        #expect(session.gameState?.opening?.button == FixTheTypo.randomButton)
        #expect(session.gameState?.status == "Sentence 2 of 5 · 1 fixed")

        session.send()
        await Support.settle(session)
        #expect(model.lastMessages.last == FixTheTypo.nextSentence, "Return leaves it to the model")
        #expect(session.nudge == "The model’s sentence came out garbled. Press Return for another.", "the next sentence came back without its typo")
        #expect(session.turns.count == 1)
        session.choose(FixTheTypo.randomButton)
        await Support.settle(session)
        #expect(session.turns.last?.cue == FixTheTypo.nextSentence)
        #expect(session.gameState?.status == "Sentence 2 of 5 · 1 fixed")
        await Support.play("pass", in: session)
        #expect(session.turns.last?.outcome == GameOutcome(text: "It was “recieve”, spelled “receive”.", youWon: false))
    }

    @Test func fixTheTypoCanHaveYouWriteTheSentences() async throws {
        let model = ScriptedModel([
            "libary → library",
            "The word “tomorow” → tomorrow",
            "yesterday → yesturday",
            "NONE",
            "hapy → happy", "freind → friend"
        ])
        let session = Support.session(model)
        session.startGame(.fixTheTypo)
        await Support.play("Too short", in: session)
        #expect(session.nudge == "A sentence of a few words, with one of them misspelled.")
        await Support.play("We will meet at the libary after lunch.", in: session)
        #expect(session.turns.first?.cue == FixTheTypo.yourGame)
        #expect(model.lastMessages == ["\(FixTheTypo.yourGame)\n\nWe will meet at the libary after lunch."])
        #expect(session.gameState?.choices == [FixTheTypo.foundIt, FixTheTypo.missedIt])
        #expect(FixTheTypo.lines(for: session.turns).map(\.text) == ["We will meet at the libary after lunch.", "The model says “libary” should be “library”."])

        session.choose(FixTheTypo.foundIt)
        #expect(session.turns.first?.outcome == GameOutcome(text: "The model found it.", youWon: false))
        #expect(session.gameState?.opening == GameOpening(placeholder: "Type your next sentence with a typo, or press Return for a random one…", button: FixTheTypo.randomButton), "you choose again for the next sentence")
        #expect(session.gameState?.status == "Sentence 2 of 5 · Model found 1")
        #expect(model.requests.count == 1)

        await Support.play("See you tomorow at the station.", in: session)
        #expect(session.turns.last?.cue == FixTheTypo.yourSentence)
        #expect(model.lastMessages.last == "\(FixTheTypo.yourSentence)\n\nSee you tomorow at the station.")
        #expect(session.turns.last?.answer == "tomorow → tomorrow")
        session.choose(FixTheTypo.foundIt)

        await Support.play("I saw it yesturday by the river.", in: session)
        #expect(session.nudge == "The model named “yesterday”, which isn’t in your sentence. Press Return to ask again.")
        #expect(session.draft == "I saw it yesturday by the river.")
        await Support.play("I saw it yesturday by the river.", in: session)
        #expect(session.turns.last?.answer == FixTheTypo.nothingWrong)
        #expect(FixTheTypo.lines(for: session.turns).last?.text == "The model found nothing misspelled.")
        session.choose(FixTheTypo.missedIt)
        await Support.play("What a hapy little dog it is.", in: session)
        session.draft = "yes"
        session.send()
        await Support.play("My best freind lives next door.", in: session)
        session.choose(FixTheTypo.missedIt)
        #expect(session.nudge == "Game done: the model found 3 of 5, and missed 2.")
        guard case .over(let outcome, _)? = session.gameState?.phase else {
            Issue.record("five sentences should end the game")
            return
        }
        #expect(outcome.youWon == false)
    }

    @Test func fixTheTypoLetsYouChooseWhoWritesEachSentence() async throws {
        let model = ScriptedModel([
            "We will meet at the libary after lunch. | libary → library",
            "tomorow → tomorrow",
            "Please recieve this gift with our thanks. | recieve → receive",
            "NONE",
            "The train leaves at seven in the evning. | evning → evening"
        ])
        let session = Support.session(model)
        session.startGame(.fixTheTypo)
        session.send()
        await Support.settle(session)
        #expect(session.turns.first?.cue == FixTheTypo.opening)
        await Support.play("library", in: session)
        #expect(session.gameState?.status == "Sentence 2 of 5 · 1 fixed")

        await Support.play("See you tomorow at the station.", in: session)
        #expect(session.turns.last?.cue == FixTheTypo.yourSentence, "a sentence of yours in the model's game")
        #expect(session.gameState?.choices == [FixTheTypo.foundIt, FixTheTypo.missedIt])
        session.choose(FixTheTypo.foundIt)
        #expect(session.gameState?.status == "Sentence 3 of 5 · 1 fixed · Model found 1")

        session.choose(FixTheTypo.randomButton)
        await Support.settle(session)
        #expect(session.turns.last?.cue == FixTheTypo.nextSentence)
        await Support.play("pass", in: session)
        await Support.play("I saw it yesturday by the river.", in: session)
        session.choose(FixTheTypo.missedIt)
        session.send()
        await Support.settle(session)
        await Support.play("evening", in: session)

        guard case .over(let outcome, let next)? = session.gameState?.phase else {
            Issue.record("five sentences should end the game")
            return
        }
        #expect(outcome == GameOutcome(text: "Game done: you fixed 2 of 3, and the model found 1 of 2. You win 3 to 2.", youWon: true))
        #expect(session.gameState?.status == "Game done · You 3 – 2 Model")
        #expect(next.placeholder.contains("new game"))
        #expect(FixTheTypo.lines(for: session.turns).map(\.text) == [
            "We will meet at the libary after lunch.", "Fixed: “libary” is “library”.",
            "See you tomorow at the station.", "The model says “tomorow” should be “tomorrow”.", "The model found it.",
            "Please recieve this gift with our thanks.", "It was “recieve”, spelled “receive”.",
            "I saw it yesturday by the river.", "The model found nothing misspelled.", "You fooled the model.",
            "The train leaves at seven in the evning.", "Fixed: “evning” is “evening”."
        ])

        var dice = GameDice(seed: 1)
        #expect(FixTheTypo.opener(after: session.turns, in: .english, dice: &dice) == .ask(FixTheTypo.newGame), "after five, a new game")
        #expect(FixTheTypo.open(with: "My best freind lives next door.", after: session.turns) == .open("My best freind lives next door.", cue: FixTheTypo.yourGame))
        #expect(FixTheTypo.open(with: "My best freind lives next door.", after: []) == .open("My best freind lives next door.", cue: FixTheTypo.yourGame))
        #expect(FixTheTypo.opener(after: [], in: .english, dice: &dice) == .ask(FixTheTypo.opening))
        #expect(FixTheTypo.systemPrompt.contains("Before each sentence the user chooses"))
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
        preferences.language = .slovak
        #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt.hasPrefix("Odd one out, in Czech.\n\nPlay the game in Slovak: "))
        session.reset()
        preferences[prompt: .chat(.agent)] = "Agents only."
        #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt == preferences.instructions(for: .chat(.llm)))
        #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).systemPrompt.hasPrefix(SystemPrompt.llm))
        #expect(session.makeRequest(asking: "Hi", images: [], of: .claudeCode).systemPrompt == "Agents only.\n\nWrite your answers in Slovak, unless the user asks for another language, as for a translation.")
        session.reset() // drops the workspace the agent's request made
    }

    @Test func stoppingTheModelsMoveTakesItBack() async {
        let session = Support.session(ScriptedModel())
        session.startGame(.fixTheTypo)
        session.send()
        session.stop()
        await Support.settle(session)
        #expect(session.turns.isEmpty)
        #expect(session.canSend, "Return asks again")
    }
}
