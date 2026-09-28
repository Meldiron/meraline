import Foundation

/// One game's numbers as Settings › Usage shows them, a tile each: its rounds and your record, what the game
/// counts of its own (`GameStat`), and your moves. Worked out here, away from the view, so tests can read them.
nonisolated struct GameInsights: Equatable, Sendable {
    let game: Game
    let tally: UsageTally.GameTally
    var locale: Locale = .current

    /// A tile: what it counts, the number, and a word on it, short enough for one line.
    struct Figure: Equatable, Sendable, Identifiable {
        let label: String
        let value: String
        let detail: String

        var id: String { label }
    }

    var figures: [Figure] {
        ([rounds] + record + own + [moves, hints] as [Figure?]).compactMap { $0 }
    }

    /// The share of decided rounds you won.
    var winRate: Double? {
        let decided = tally.roundsWon + tally.roundsLost
        return decided > 0 ? Double(tally.roundsWon) / Double(decided) : nil
    }

    /// What a tile can't say.
    var footnote: String? {
        switch game {
        case .speedDefinitions where tally[.rated] > 0: "A definition lands at \(SpeedDefinitions.passMark)/10 or better."
        case .longestWord where tally[.compared] > 0: "Best word found counts the rounds your word was as long as the longest this Mac knows in the letters."
        default: nil
        }
    }

    // MARK: Every game's

    private var rounds: Figure {
        let name = game.roundsName
        let detail: String
        if tally.rounds == 0 {
            detail = "none finished yet"
        } else if game.isScoredOnly {
            detail = "\(compact(tally[.opened])) \(game == .addAWord ? "started" : "opened") by you"
        } else {
            detail = "won \(compact(tally.roundsWon)), lost \(compact(tally.roundsLost))"
        }
        return Figure(label: name.prefix(1).uppercased() + name.dropFirst(), value: compact(tally.rounds), detail: detail)
    }

    /// The share of rounds won, and the most won in a row, for a game whose rounds are won and lost.
    private var record: [Figure?] {
        guard !game.isScoredOnly, let winRate else { return [] }
        let decided = tally.roundsWon + tally.roundsLost
        return [
            Figure(
                label: "Win rate",
                value: UsageInsights.percent(winRate, locale: locale),
                detail: tally.roundsDrawn > 0 ? "not counting \(count(tally.roundsDrawn, "draw"))" : "of \(count(decided, game.roundName, game.roundsName))"
            ),
            Figure(label: "Best run", value: compact(tally.winStreak), detail: tally.winStreak == 0 ? "no wins yet" : tally.winStreak == 1 ? "win in a row" : "wins in a row")
        ]
    }

    private var moves: Figure {
        Figure(label: "Moves", value: compact(tally.moves), detail: tally.rejectedMoves > 0 ? "\(compact(tally.rejectedMoves)) came back" : "none came back")
    }

    private var hints: Figure? {
        guard tally.hints > 0 else { return nil }
        return Figure(label: "Hints", value: compact(tally.hints), detail: tally.rounds > 0 ? "about \(average(tally.hints, over: tally.rounds)) a \(game.roundName)" : "")
    }

    // MARK: The game's own

    private var own: [Figure?] {
        switch game {
        case .rhymeDuel:
            [score("Average score")]
        case .addAWord:
            [
                score("Average sense"),
                perRound("Words", .words),
                best("Longest sentence", .words, "word")
            ]
        case .categories:
            [
                perRound("Things named", .named),
                tally.rounds > 0 ? Figure(label: "Your categories", value: compact(tally[.opened]), detail: "of \(count(tally.rounds, "round"))") : nil
            ]
        case .wordFootball:
            [
                perRound("Your words", .words),
                best("Longest match", .chain, "word played", "words played")
            ]
        case .oddOneOut:
            [
                share("Spotted", .spotted, of: .theirPuzzles, "it set"),
                share("Fooled the model", .fooled, of: .yourPuzzles, "you set")
            ]
        case .fixTheTypo:
            [
                share("Typos fixed", .fixed, of: .theirPuzzles, "it wrote"),
                share("Fooled the model", .fooled, of: .yourPuzzles, "you wrote")
            ]
        case .speedDefinitions:
            [
                share("Definitions landed", .landed, of: .theirPuzzles, "words"),
                score("Average grade", best: tally.best(.points).map { "best game \($0)/\(SpeedDefinitions.roundLimit * 10)" }),
                share("Stumped the model", .fooled, of: .yourPuzzles, "you gave")
            ]
        case .longestWord:
            [
                length("Your words", .letters, over: .words),
                best("Your longest", .letters, "letter"),
                length("Model’s words", .modelLetters, over: .modelWords),
                share("Best word found", .bestFound, of: .compared, "rounds")
            ]
        }
    }

    /// The model's scores out of 10 on average, and the best, or `best` in its place.
    private func score(_ label: String, best: String? = nil) -> Figure? {
        guard tally[.rated] > 0 else { return nil }
        return Figure(
            label: label,
            value: "\(average(tally[.score], over: tally[.rated]))/10",
            detail: best ?? tally.best(.score).map { "best \($0)/10" } ?? ""
        )
    }

    /// A count, and about how many a round.
    private func perRound(_ label: String, _ stat: GameStat) -> Figure? {
        guard tally.rounds > 0 else { return nil }
        return Figure(label: label, value: compact(tally[stat]), detail: "about \(average(tally[stat], over: tally.rounds)) a \(game.roundName)")
    }

    /// The most a round has had.
    private func best(_ label: String, _ stat: GameStat, _ unit: String, _ units: String? = nil) -> Figure? {
        guard let best = tally.best(stat) else { return nil }
        return Figure(label: label, value: compact(best), detail: best == 1 ? unit : units ?? unit + "s")
    }

    /// How many of some went your way: the puzzles you spotted of those the model set.
    private func share(_ label: String, _ stat: GameStat, of total: GameStat, _ what: String) -> Figure? {
        guard tally[total] > 0 else { return nil }
        return Figure(label: label, value: compact(tally[stat]), detail: "of \(compact(tally[total])) \(what)")
    }

    /// Letters a word on average.
    private func length(_ label: String, _ letters: GameStat, over words: GameStat) -> Figure? {
        guard tally[words] > 0 else { return nil }
        return Figure(label: label, value: average(tally[letters], over: tally[words]), detail: "letters on average")
    }

    private func compact(_ number: Int) -> String {
        UsageInsights.compact(number, locale: locale)
    }

    private func count(_ number: Int, _ singular: String, _ plural: String? = nil) -> String {
        UsageInsights.count(number, singular, plural, locale: locale)
    }

    private func average(_ total: Int, over count: Int) -> String {
        UsageInsights.average(total, over: count, locale: locale)
    }
}
