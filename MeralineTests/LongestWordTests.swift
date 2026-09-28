import Foundation
import Testing
@testable import Meraline

struct LongestWordRulesTests {
    private typealias Support = GameTestSupport

    /// A round the model has picked for: the letters in the cue's aside, and its word as the reply.
    static func round(_ letters: String, model: String, in language: AnswerLanguage = .english) -> [ChatSession.Turn] {
        var turn = Support.turn(cue: LongestWord.opening, reply: model)
        turn.aside = "\(LongestWord.lettersIntro)\(LongestWord.spaced(Array(letters))). \(LongestWord.languageIntro)\(language.name)."
        return [turn]
    }

    private static let letters = "drapeksto"

    @Test func drawsNineLettersWithVowelsAndAWordWorthFinding() {
        for seed in UInt64(1)...12 {
            var dice = GameDice(seed: seed)
            let letters = LongestWord.draw(dice: &dice, in: .english)
            #expect(letters.count == LongestWord.letterCount)
            let vowels = letters.filter { "aeiou".contains($0) }
            #expect((3...4).contains(vowels.count), "\(String(letters))")
            #expect(Set(letters).allSatisfy { letter in letters.filter { $0 == letter }.count <= (vowels.contains(letter) ? 3 : 2) })
            #expect(!letters.contains("q") || letters.contains("u"))
            #expect((WordCheck.longestWords(from: letters).first?.count ?? 0) >= 6, "\(String(letters)) hides a word of six letters")
        }
    }

    @Test func theAsideCarriesTheLettersAndTheLanguage() throws {
        var dice = GameDice(seed: 3)
        let aside = try #require(LongestWord.aside(for: Support.turn(cue: LongestWord.opening), after: [], in: .czech, dice: &dice))
        #expect(aside.hasPrefix(LongestWord.lettersIntro))
        #expect(aside.hasSuffix("\(LongestWord.languageIntro)Czech."))
        var turn = Support.turn(cue: LongestWord.opening)
        turn.aside = aside
        #expect(LongestWord.letters(of: [turn])?.count == LongestWord.letterCount)
        #expect(LongestWord.language(of: [turn]) == .czech)
        #expect(LongestWord.aside(for: Support.turn("parked"), after: [turn], in: .english, dice: &dice) == nil, "only a round's cue draws")
    }

    @Test func yourWordIsCheckedOnThisMac() {
        let round = Self.round(Self.letters, model: "DRAPE")
        #expect(LongestWord.play("Parked!", in: round, insisting: false) == .record("PARKED", outcome: GameOutcome(text: "Your PARKED beats the model’s DRAPE, 6 letters to 5.", youWon: true)))
        #expect(LongestWord.play("zoo", in: round, insisting: false) == .reject("The letters can’t make “ZOO”: there’s no “Z” or “O” to spare."))
        #expect(LongestWord.play("tsdrk", in: round, insisting: false) == .reject("“TSDRK” isn’t in this Mac’s dictionary. Try another, or send it again to count it anyway."))
        #expect(LongestWord.play("tsdrk", in: round, insisting: true) == .record("TSDRK", outcome: GameOutcome(text: "A tie: TSDRK and DRAPE, 5 letters each.", youWon: nil)), "sent again, it counts")
        #expect(LongestWord.play("zoo", in: round, insisting: true) == .reject("The letters can’t make “ZOO”: there’s no “Z” or “O” to spare."), "the letters never bend")
        var insisted = round
        insisted.append(Support.turn("TSDRK", outcome: GameOutcome(text: "A tie.", youWon: nil)))
        #expect(LongestWord.lines(for: insisted).map(\.text).contains("You: TSDRK, 5 letters"))
        #expect(LongestWord.play("red tape", in: round, insisting: false) == .reject("One word, please."))
        #expect(LongestWord.play("a", in: round, insisting: false) == .reject("A word of two letters or more."))
        #expect(LongestWord.play("pass", in: round, insisting: false) == .record("pass", outcome: GameOutcome(text: "You passed, and the model’s DRAPE takes it, 5 letters.", youWon: false)))
        #expect(LongestWord.play("parked", in: [], insisting: false) == .reject("Wait for the letters."))
    }

    @Test func theLongerWordWinsAndAWordThatDoesntCountLoses() {
        let letters = Array(Self.letters)
        func outcome(_ yours: String?, _ model: String?) -> GameOutcome {
            LongestWord.outcome(yours: yours, model: model, letters: letters, in: .english)
        }
        #expect(outcome("drape", "PARKED") == GameOutcome(text: "The model’s PARKED beats your DRAPE, 6 letters to 5.", youWon: false))
        #expect(outcome("drape", "DRAPE") == GameOutcome(text: "A tie: you both found DRAPE.", youWon: nil))
        #expect(outcome("drape", "SPOKE") == GameOutcome(text: "A tie: DRAPE and SPOKE, 5 letters each.", youWon: nil))
        #expect(outcome("drape", "PAIRED") == GameOutcome(text: "The model’s PAIRED needs letters that aren’t there, so your DRAPE wins.", youWon: true))
        #expect(outcome("drape", "TSDRK") == GameOutcome(text: "The model’s TSDRK isn’t in this Mac’s dictionary, so your DRAPE wins.", youWon: true))
        #expect(outcome("drape", nil) == GameOutcome(text: "The model found no word, so your DRAPE wins.", youWon: true))
        #expect(outcome(nil, nil) == GameOutcome(text: "You passed, and the model found no word either.", youWon: nil))
    }

    @Test func theModelsWordIsReadFromItsReply() {
        let letters = Array(Self.letters)
        #expect(LongestWord.word(inReply: "My word is DRAPE.", letters: letters) == "DRAPE")
        #expect(LongestWord.word(inReply: "**drape**", letters: letters) == "drape")
        #expect(LongestWord.word(inReply: "I'd say drape, or even parked", letters: letters) == "parked", "the longest the letters pay for")
        let round = Self.round(Self.letters, model: "")
        #expect(LongestWord.judge("PARKED\n\nSix letters!", in: round) == .accept("PARKED"))
        #expect(LongestWord.judge("drape", in: round) == .accept("DRAPE"))
        #expect(LongestWord.judge("PASS", in: round) == .accept(LongestWord.noWord))
        #expect(LongestWord.modelWord(in: Self.round(Self.letters, model: LongestWord.noWord)) == nil)
    }

    @Test func hintsAndTheLongerWordComeFromThisMac() throws {
        let letters = Array(Self.letters)
        let best = try #require(WordCheck.longestWords(from: letters).first)
        #expect(best.count >= 6)
        #expect(LongestWord.spending(best, from: letters) != nil)
        let hints = LongestWord.hints(for: letters, in: .english)
        #expect(hints.first == "This Mac knows a word of \(best.count) letters in these.")
        #expect(hints.contains("A word of \(best.count) letters starts with “\(best.prefix(2).uppercased())”."))
        #expect(LongestWord.hints(for: letters, in: .czech).isEmpty, "the word list is English")

        var round = Self.round(Self.letters, model: "DRAPE")
        round.append(Support.turn("SPOKE", outcome: GameOutcome(text: "A tie.", youWon: nil)))
        #expect(LongestWord.longer(than: round, letters: letters) == best)
        round[1] = Support.turn(best.uppercased(), outcome: GameOutcome(text: "You win.", youWon: true))
        #expect(LongestWord.longer(than: round, letters: letters) == nil, "nothing longer than yours")
    }

    @Test func thisMacKnowsWordsAndTheirForms() {
        #expect(WordCheck.isWord("parked", in: .english) == true)
        #expect(WordCheck.isWord("stones", in: .english) == true, "forms the word list leaves out")
        #expect(WordCheck.isWord("fei", in: .english) == false)
        let words = WordCheck.longestWords(from: Array("parkedxyz"))
        #expect(words.first == "parked", "park, as the word list has it, and its past")
        #expect(words.allSatisfy { LongestWord.spending($0, from: Array("parkedxyz")) != nil })
    }
}

@MainActor
struct LongestWordSessionTests {
    private typealias Support = GameTestSupport

    @Test func theModelPicksFirstAndItsWordStaysHiddenUntilYoursIsIn() async throws {
        let model = ScriptedModel(["DRAPE", "SPOKE"])
        let session = Support.session(model)
        session.dice = GameDice(seed: 2)
        session.startGame(.longestWord)
        #expect(model.requests.count == 1, "the model picks at once")
        #expect(model.requests.first?.systemPrompt == LongestWord.systemPrompt)
        let asked = try #require(session.turns.first?.message)
        #expect(asked.hasPrefix("\(LongestWord.opening)\n\n\(LongestWord.lettersIntro)"))
        #expect(asked.hasSuffix("\(LongestWord.languageIntro)English."))
        let letters = try #require(LongestWord.letters(of: session.turns))
        #expect(LongestWord.lines(for: session.turns).map(\.text) == ["Round 1", LongestWord.spaced(letters)], "the letters show while the model picks")
        #expect(session.nudge == LongestWord.invitation)

        await Support.settle(session)
        #expect(session.isYourMove)
        #expect(session.canHint)
        #expect(LongestWord.lines(for: session.turns).map(\.text) == ["Round 1", LongestWord.spaced(letters), "The model has picked its word."])
        #expect(session.conversationMarkdown?.contains("DRAPE") == false, "hidden until you play")

        let best = try #require(WordCheck.longestWords(from: letters).first)
        await Support.play(best, in: session)
        #expect(model.requests.count == 1, "your word is judged on this Mac")
        let outcome = try #require(session.turns.last?.outcome)
        #expect(session.nudge == outcome.text)
        #expect(session.gameState?.status == "Round 1 done")
        let lines = LongestWord.lines(for: session.turns).map(\.text)
        #expect(lines.contains("You: \(best.uppercased()), \(best.count) letters"))
        #expect(lines.contains { $0.hasPrefix("Model: DRAPE") })
        #expect(!lines.contains { $0.hasPrefix("This Mac knows a longer one") }, "yours is the longest it knows")
        #expect(session.rematch != nil, "Play Again deals new letters")

        session.send()
        #expect(model.requests.count == 2)
        let next = try #require(session.turns.last)
        #expect(next.cue == LongestWord.nextRound)
        #expect(next.message.hasPrefix("\(LongestWord.nextRound)\n\n\(LongestWord.lettersIntro)"))
        #expect(model.lastMessages == [asked, "DRAPE", "\(best.uppercased())\n\n\(next.message)"], "the model reads your word only after it picked")
        await Support.settle(session)
        #expect(LongestWord.lines(for: session.turns).map(\.text).contains("Round 2"))
    }

    @Test func theLettersShuffleOnlyUntilYourWordIsIn() async throws {
        let session = Support.session(ScriptedModel(["DRAPE"]))
        session.dice = GameDice(seed: 2)
        session.startGame(.longestWord)
        let letters = try #require(LongestWord.letters(of: session.turns))
        #expect(LongestWord.lines(for: session.turns)[1].kind == .tiles(shuffles: true), "you can shuffle while the model picks")
        #expect(LongestWord.lines(for: session.turns)[1].pieces.filter { $0.voice == .model }.map(\.text) == letters.map { $0.uppercased() })

        await Support.settle(session)
        await Support.play(try #require(WordCheck.longestWords(from: letters).first), in: session)
        #expect(LongestWord.lines(for: session.turns)[1].kind == .tiles(shuffles: false), "the round is over")
    }

    @Test func aModelThatFailsToPickIsAskedAgain() async {
        let session = Support.session(ScriptedModel())
        session.startGame(.longestWord)
        await Support.settle(session)
        #expect(session.turns.isEmpty, "the failed pick is taken back")
        #expect(session.failure != nil)
        #expect(session.canSend, "Return asks again")
    }
}
