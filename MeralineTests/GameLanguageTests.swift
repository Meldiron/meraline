import Foundation
import Testing
@testable import Meraline

/// The games in another language than English: nothing of the English lists reaches the model or the board.
@MainActor
struct GameLanguageTests {
    private typealias Support = GameTestSupport

    private func czechSession(_ model: ScriptedModel) -> ChatSession {
        let preferences = Support.preferences()
        preferences.language = .czech
        return ChatSession(preferences: preferences) { model.stream($0) }
    }

    @Test func aDuelInCzechDrawsItsStoryButNoEnglishRhymes() throws {
        var dice = GameDice(seed: 2)
        let story = try #require(RhymeDuel.aside(for: Support.turn(cue: RhymeDuel.opening), after: [], in: .czech, dice: &dice))
        #expect(story.hasPrefix("This duel’s story: "))
        #expect(!story.contains("End your line"))
        let duel = [Support.turn(cue: RhymeDuel.opening, reply: "Byl jednou jeden den | sen, len")]
        #expect(RhymeDuel.aside(for: Support.turn("Kdy přišel velký sen"), after: duel, in: .czech, dice: &dice) == nil, "the model picks its own ending")
        let yours = Support.turn("Byl jednou jeden den", cue: RhymeDuel.yourOpening)
        #expect(RhymeDuel.aside(for: yours, after: [], in: .czech, dice: &dice) == "End your line on a word that rhymes with “den”.")
        #expect(RhymeDuel.aside(for: Support.turn("Once there was a pen", cue: RhymeDuel.yourOpening), after: [], in: .english, dice: &dice)?.hasPrefix("End your line on one of these words: ") == true)
    }

    @Test func aCzechLineGetsOnlyTheModelsRhymesAsHints() {
        let session = Support.session(ScriptedModel())
        session.reopen(ChatSession.PastChat(turns: [Support.turn(cue: RhymeDuel.opening, reply: "Byl jednou jeden den | sen, len")], date: .now, mode: .game(.rhymeDuel)))
        #expect(session.gameState?.hints == ["Try ending your line on “sen” or “len”."], "“den” is in an English family, which wasn't offered")
        #expect(RhymeDuel.rhymes("rád", with: "hrad"), "accents aside")
        #expect(RhymeDuel.complaint(about: "Mám tě moc rád", after: .init(line: "Stál tam starý hrad")) == nil)
    }

    @Test func wordFootballInCzechHasTheModelKickOff() async throws {
        let model = ScriptedModel(["Kůň.", "OK: ešus"])
        let session = czechSession(model)
        session.startGame(.wordFootball)
        session.send()
        let kickoff = try #require(session.turns.first)
        #expect(kickoff.cue == WordFootball.opening, "no English word is drawn")
        #expect(kickoff.message.hasPrefix("\(WordFootball.opening)\n\nKick off with a common word, "))
        #expect(model.requests.first?.systemPrompt.contains("Play the game in Czech") == true)
        await Support.settle(session)
        #expect(session.turns.first?.answer == "kůň")
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “N”…"), "“ň” counts as “n”")
        await Support.play("Nebe", in: session)
        #expect(session.gameState?.phase == .yourMove(placeholder: "A word starting with “S”…"))
    }

    @Test func addAWordInCzechHasTheModelStartWithASubject() async throws {
        let model = ScriptedModel(["Včera"])
        let session = czechSession(model)
        session.startGame(.addAWord)
        session.choose(AddAWord.randomButton)
        let first = try #require(session.turns.first)
        #expect(first.cue == AddAWord.opening)
        #expect(first.message.hasPrefix("\(AddAWord.opening)\n\nThis sentence’s subject: "))
        await Support.settle(session)
        #expect(session.isYourMove)
        #expect(AddAWord.lines(for: session.turns).map(\.text) == ["Včera"])
        var dice = GameDice(seed: 1)
        #expect(AddAWord.aside(for: Support.turn(cue: AddAWord.nextSentence), after: session.turns, in: .czech, dice: &dice) == nil, "no subject for the next sentence, and no story until one is finished")
    }

    @Test func categoriesInCzechNameTheDrawnCategoryInCzech() async throws {
        let model = ScriptedModel(["Věci v kuchyni | OK: lžíce"])
        let session = czechSession(model)
        session.dice = GameDice(seed: 4)
        session.startGame(.categories)
        session.send()
        let first = try #require(session.turns.first)
        let drawn = try #require(Categories.drawnCategory(of: first))
        #expect(first.message.hasSuffix("“\(drawn)”. Reply with its name in Czech, then “ | ”, then “OK: ” and the first thing in it."))
        await Support.settle(session)
        #expect(session.turns.first?.answer == "Věci v kuchyni | OK: lžíce")
        #expect(session.gameState?.status == "Věci v kuchyni · 1 of 12")
        #expect(Categories.lines(for: session.turns).map(\.text) == ["Věci v kuchyni", "lžíce"])

        var dice = GameDice(seed: 1)
        let played = Categories.categories.dropLast().map { category in
            var turn = Support.turn(cue: Categories.randomCategory, reply: "Něco | OK: jedno")
            turn.aside = "This round’s category: “\(category)”."
            return [turn, Support.turn("pass", outcome: GameOutcome(text: "Passed", youWon: false))]
        }.joined()
        let next = try #require(Categories.aside(for: Support.turn(cue: Categories.randomCategory), after: Array(played), in: .czech, dice: &dice))
        #expect(next.hasPrefix("This round’s category: “\(try #require(Categories.categories.last))”."), "what was played is known by its English name")
    }

    @Test func speedDefinitionsInCzechAsksForAWordOfTheDifficulty() throws {
        var dice = GameDice(seed: 3)
        var turn = Support.turn(cue: SpeedDefinitions.opening)
        turn.aside = try #require(SpeedDefinitions.aside(for: turn, after: [], in: .czech, dice: &dice))
        #expect(turn.aside?.hasPrefix("Pick a word of ") == true)
        #expect(turn.aside?.contains(", to do with ") == true)
        #expect(!SpeedDefinitions.Difficulty.allCases.flatMap(\.words).contains { turn.aside?.contains("“\($0)”") == true }, "no English words")
        #expect(SpeedDefinitions.Difficulty(of: turn) != nil, "the heading still says how hard")
    }

    @Test func longestWordSpendsAccentedLettersAsPlainOnesAndChecksTheRoundsLanguage() {
        #expect(LongestWord.spelled("Kůň") == "kun")
        #expect(LongestWord.spending(LongestWord.spelled("Kůň"), from: Array("kunabcdef")) != nil)
        #expect(LongestWord.systemPrompt.contains("A letter with an accent counts as the same letter without it"))
        let round = LongestWordRulesTests.round("kunabcdef", model: "KŮŇ", in: .czech)
        #expect(LongestWord.language(of: round) == .czech)
        #expect(LongestWord.hints(for: Array("kunabcdef"), in: .czech).isEmpty)
        #expect([nil, "cs"].contains(WordCheck.spellChecker(for: .czech)), "a Czech round asks the Czech dictionary, when this Mac has one")
    }

    @Test func aGameInAnotherLanguageReadsEnglishInItsRulesAsThatLanguage() throws {
        let line = try #require(AnswerLanguage.slovak.instruction(for: .game(.longestWord)))
        #expect(line.contains("where the rules above say English, read Slovak"))
        #expect(AnswerLanguage.english.instruction(for: .game(.longestWord)) == nil)
    }
}
