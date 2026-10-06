import Foundation
import Testing
@testable import Meraline

/// Each game's own numbers in the usage ledger, and the tiles Settings › Usage makes of them.
struct GameFiguresTests {
    private typealias Support = GameTestSupport
    private typealias GameTally = UsageTally.GameTally
    private let us = Locale(identifier: "en_US")

    @Test func winsInARowAddUpInOrder() {
        var tally = GameTally()
        for won in [true, true, false, true, true, true, nil] as [Bool?] { tally.count(round: won) }
        #expect(tally.roundsWon == 5 && tally.roundsLost == 1 && tally.roundsDrawn == 1)
        #expect(tally.winStreak == 3 && tally.winsAtStart == 2 && tally.winsAtEnd == 0, "a draw ends a run too")

        var early = GameTally()
        for won in [false, true, true] { early.count(round: won) }
        var late = GameTally()
        for won in [true, false] { late.count(round: won) }
        #expect((early + late).winStreak == 3, "a run carries on from one tally into the next")
        #expect((late + early).winStreak == 2)
        #expect((GameTally() + early) == early && (early + GameTally()) == early)
    }

    @Test func aSpanSumsItsSlotsFromTheEarliest() {
        let ledger = UsageLedger(file: nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let results: [Bool?] = [true, false, true, true, true, true, false, true, true, nil, true]
        for (index, won) in results.enumerated() {
            let when = now.addingTimeInterval(TimeInterval(index - results.count) * UsageLedger.slotLength)
            ledger.record(at: when) { $0.games["longestWord", default: .init()].count(round: won) }
        }
        #expect(ledger.summary(.day, now: now).games["longestWord"]?.winStreak == 4)
        #expect(ledger.allTime.games["longestWord"]?.winStreak == 4)
        #expect(ledger.summary(.day, now: now).games["longestWord"]?.winsAtEnd == 1)
    }

    @Test func figuresAddUpAndOlderFilesReadAsNone() throws {
        var figures = GameFigures()
        figures.add(1, to: .rated)
        figures.record(6, as: .score)
        var tally = GameTally()
        tally.count(round: nil, with: figures)
        figures.counts[.score] = 0
        figures.record(8, as: .score)
        tally.count(round: nil, with: figures)
        #expect(tally[.rated] == 2 && tally[.score] == 14 && tally.best(.score) == 8)
        #expect(tally[.words] == 0 && tally.best(.words) == nil)

        let kept = try JSONDecoder().decode(GameTally.self, from: JSONEncoder().encode(tally))
        #expect(kept == tally)
        #expect(Set(tally.counts.keys) == ["rated", "score"], "the ledger keeps names of numbers, never words")

        let older = try JSONDecoder().decode(GameTally.self, from: Data(#"{"roundsWon": 2, "hints": 1}"#.utf8))
        #expect(older.roundsWon == 2 && older.winStreak == 0 && older.counts.isEmpty && older.bests.isEmpty)
    }

    // MARK: What each game counts

    @Test func aDuelCountsItsScoreAndWhoOpened() {
        var duel = [Support.turn(cue: RhymeDuel.opening, reply: "The cat sat waiting by the door | floor, more")]
        for line in 1...3 { duel.append(Support.turn("My line number \(line) ends on more", reply: "The model sings its line \(line) | sing, ring")) }
        duel.append(Support.turn("And that is all there is, no more", reply: "Score: 6/10 — fewer words, a steadier beat"))
        let figures = Game.rhymeDuel.figures(ofRoundEndingIn: duel)
        #expect(figures.counts == [.rated: 1, .score: 6] && figures.bests == [.score: 6], "the model opened, so nothing counts as yours")
    }

    @Test func aSentenceCountsItsWordsAndSense() {
        let sentence = [
            Support.turn("Yesterday", cue: AddAWord.yourOpening, reply: "my"),
            Support.turn("grandmother", reply: "danced.\nScore: 7/10 — lively, if unlikely")
        ]
        let figures = Game.addAWord.figures(ofRoundEndingIn: sentence)
        #expect(figures.counts == [.opened: 1, .words: 4, .rated: 1, .score: 7])
        #expect(figures.bests == [.words: 4, .score: 7])
    }

    @Test func categoriesAndFootballCountYourWords() {
        let kitchen = Support.turn("Kitchen", cue: Categories.yourCategory, reply: "OK: spoon")
        let five = (1...5).map { Support.turn("mine \($0)", reply: "OK: theirs \($0)") }
        let round = [kitchen] + five + [Support.turn("mine 6", reply: "OK")]
        #expect(Game.categories.figures(ofRoundEndingIn: round).counts == [.opened: 1, .named: 6], "the category is no thing named")

        // The model's salmon fouls twice, so the foul stands and the chain ends on it.
        let match = [
            Support.turn("banana", cue: WordFootball.yourKickoff, reply: "OK: apple"), Support.turn("egg", reply: "OK: salmon"),
            Support.turn(cue: WordFootball.retryCue(for: "salmon", startingWith: "g", repeated: false), reply: "OK: salmon"),
        ]
        let figures = Game.wordFootball.figures(ofRoundEndingIn: match)
        #expect(figures.counts == [.words: 2, .chain: 3] && figures.bests == [.chain: 3], "three words after the kickoff")
    }

    @Test func puzzlesCountWhatWentYourWay() {
        let puzzle = "apple · hammer · banana | hammer: not a fruit"
        var game: [ChatSession.Turn] = []
        for round in 0..<6 {
            if round.isMultiple(of: 2) {
                game.append(Support.turn(cue: round == 0 ? OddOneOut.opening : OddOneOut.nextPuzzle, reply: puzzle, outcome: GameOutcome(text: "Right", youWon: round < 4)))
            } else {
                game.append(Support.turn("pear, plum, piano", reply: "piano: not a fruit", outcome: GameOutcome(text: "Got it", youWon: round == 1)))
            }
        }
        #expect(Game.oddOneOut.figures(ofRoundEndingIn: game).counts == [.theirPuzzles: 3, .spotted: 2, .yourPuzzles: 3, .fooled: 1])

        let typos = [
            Support.turn(cue: FixTheTypo.opening, reply: "We met at the libary. | libary → library", outcome: GameOutcome(text: "Fixed", youWon: true)),
            Support.turn("I red the whole book", cue: FixTheTypo.yourSentence, reply: "red → read", outcome: GameOutcome(text: "Found", youWon: false)),
            Support.turn(cue: FixTheTypo.nextSentence, reply: "The wether is fine. | wether → weather", outcome: GameOutcome(text: "Missed", youWon: false))
        ]
        #expect(Game.fixTheTypo.figures(ofRoundEndingIn: typos).counts == [.theirPuzzles: 2, .fixed: 1, .yourPuzzles: 1, .fooled: 0])
    }

    @Test func speedDefinitionsCountsGradesOrStumps() {
        let theirs = [
            Support.turn(cue: SpeedDefinitions.opening, reply: "serendipity | finding something good by chance"),
            Support.turn("a lucky find", reply: "8/10 — nails it"),
            Support.turn(cue: SpeedDefinitions.nextWord, reply: "ladder | steps to climb"),
            Support.turn("a thing", reply: "4/10 — too vague")
        ]
        let graded = Game.speedDefinitions.figures(ofRoundEndingIn: theirs)
        #expect(graded.counts == [.theirPuzzles: 2, .landed: 1, .rated: 2, .score: 12, .points: 12] && graded.bests == [.points: 12])

        let yours = [
            Support.turn("serendipity", cue: SpeedDefinitions.yourGame, reply: "finding good by chance", outcome: GameOutcome(text: "Got it", youWon: false)),
            Support.turn("ennui", reply: "a deep thought", outcome: GameOutcome(text: "Stumped", youWon: true))
        ]
        #expect(Game.speedDefinitions.figures(ofRoundEndingIn: yours).counts == [.yourPuzzles: 2, .fooled: 1])
    }

    @Test func aPlayedGameCountsItsFiguresInTheLedger() async throws {
        let usage = UsageLedger(file: nil)
        let session = Support.session(ScriptedModel(["ZZZZZZZZZ"]), usage: usage)
        session.dice = GameDice(seed: 2)
        session.startGame(.longestWord)
        await Support.settle(session)
        let letters = try #require(LongestWord.letters(of: session.turns))
        let best = try #require(WordCheck.longestWords(from: letters).first)
        await Support.play(best, in: session)
        let scores = try #require(usage.allTime.games["longestWord"])
        #expect(scores.roundsWon == 1 && scores.winStreak == 1, "the model found no word in the letters")
        #expect(scores[.words] == 1 && scores[.letters] == best.count && scores.best(.letters) == best.count)
        #expect(scores[.compared] == 1 && scores[.bestFound] == 1)
        #expect(scores[.modelWords] == 0)
    }

    // MARK: The tiles

    @Test func aGameWonAndLostShowsItsRecordAndItsOwnNumbers() {
        let tally = GameTally(
            roundsWon: 2, roundsLost: 1, roundsDrawn: 1, moves: 5, rejectedMoves: 1, hints: 2, winStreak: 2,
            counts: ["words": 3, "letters": 20, "modelWords": 4, "modelLetters": 22, "compared": 4, "bestFound": 1],
            bests: ["letters": 8]
        )
        let insights = GameInsights(game: .longestWord, tally: tally, locale: us)
        #expect(insights.figures.map(\.label) == ["Rounds", "Win rate", "Best run", "Your words", "Your longest", "Model’s words", "Best word found", "Moves", "Hints"])
        #expect(insights.figures.map(\.value) == ["4", "67%", "2", "6.7", "8", "5.5", "1", "5", "2"])
        #expect(insights.figures.map(\.detail) == [
            "won 2, lost 1", "not counting 1 draw", "wins in a row", "letters on average", "letters", "letters on average",
            "of 4 rounds", "1 came back", "about 0.5 a round"
        ])
        #expect(insights.footnote?.hasPrefix("Best word found") == true)
    }

    @Test func aScoredGameShowsItsScoresInsteadOfARecord() {
        let tally = GameTally(roundsDrawn: 3, moves: 12, counts: ["opened": 1, "rated": 2, "score": 13], bests: ["score": 7])
        let insights = GameInsights(game: .rhymeDuel, tally: tally, locale: us)
        #expect(insights.figures.map(\.label) == ["Duels", "Average score", "Moves"])
        #expect(insights.figures.map(\.value) == ["3", "6.5/10", "12"])
        #expect(insights.figures.map(\.detail) == ["1 opened by you", "best 7/10", "none came back"])
        #expect(insights.footnote == nil)

        let started = GameInsights(game: .speedDefinitions, tally: GameTally(started: 1), locale: us)
        #expect(started.figures.map(\.label) == ["Games", "Moves"])
        #expect(started.figures.first?.detail == "none finished yet")
    }

    @Test func everyTileSaysItsWordOnOneLine() {
        var counts: [String: Int] = [:]
        var bests: [String: Int] = [:]
        for stat in GameStat.allCases {
            counts[stat.rawValue] = 876
            bests[stat.rawValue] = 42
        }
        let tally = GameTally(started: 900, roundsWon: 412, roundsLost: 388, roundsDrawn: 99, moves: 9_876, rejectedMoves: 321, hints: 777, winStreak: 23, counts: counts, bests: bests)
        for game in Game.allCases {
            for figure in GameInsights(game: game, tally: tally, locale: us).figures {
                #expect(figure.detail.count <= 22, "\(game.title) › \(figure.label): “\(figure.detail)” wraps in a tile")
            }
        }
    }
}
