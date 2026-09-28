import Foundation

/// The numbers a game counts of its own when a round ends, besides who won it: a duel's score, the letters of
/// your word, the puzzles you solved. Their raw values are keys in the usage ledger, so they never change. Only
/// how many, never which words.
nonisolated enum GameStat: String, CaseIterable, Sendable {
    /// Rounds you opened: duels whose rhymes you set, sentences you started, categories you named.
    case opened
    /// Rounds or definitions the model scored out of 10, and their scores added up.
    case rated
    case score
    /// A Speed Definitions game's grades added up, out of 50.
    case points
    /// Words: every word of an Add-a-Word sentence, yours in a Word Football match, your Longest Word words.
    case words
    /// Letters of your Longest Word words, and the model's words that counted and their letters.
    case letters
    case modelWords
    case modelLetters
    /// Longest Word rounds whose letters this Mac knows a longest word in, and those your word was as long.
    case compared
    case bestFound
    /// Things you named in Categories.
    case named
    /// Words played in a Word Football match after its kickoff.
    case chain
    /// Puzzles the model set, or words it gave, and how many you solved or defined well.
    case theirPuzzles
    case spotted
    case fixed
    case landed
    /// Puzzles you set, sentences you wrote, or words you gave, and how many the model missed.
    case yourPuzzles
    case fooled
}

/// What one round adds to its game's numbers: counts to add up, and records to keep the most of.
nonisolated struct GameFigures: Equatable, Sendable {
    var counts: [GameStat: Int] = [:]
    var bests: [GameStat: Int] = [:]

    mutating func add(_ number: Int, to stat: GameStat) {
        counts[stat, default: 0] += number
    }

    /// Counts `number` and keeps it as the round's record for `stat`.
    mutating func record(_ number: Int, as stat: GameStat) {
        add(number, to: stat)
        bests[stat] = max(bests[stat] ?? number, number)
    }
}

nonisolated extension Game {
    /// What the round that just ended makes of the game's numbers, worked out from the turns as its rules are.
    func figures(ofRoundEndingIn turns: [ChatSession.Turn]) -> GameFigures {
        switch self {
        case .rhymeDuel: RhymeDuel.figures(ofRoundEndingIn: turns)
        case .addAWord: AddAWord.figures(ofRoundEndingIn: turns)
        case .categories: Categories.figures(ofRoundEndingIn: turns)
        case .wordFootball: WordFootball.figures(ofRoundEndingIn: turns)
        case .oddOneOut: OddOneOut.figures(ofRoundEndingIn: turns)
        case .fixTheTypo: FixTheTypo.figures(ofRoundEndingIn: turns)
        case .speedDefinitions: SpeedDefinitions.figures(ofRoundEndingIn: turns)
        case .longestWord: LongestWord.figures(ofRoundEndingIn: turns)
        }
    }

    /// What one of the game's rounds is called, and more than one.
    var roundName: String {
        switch self {
        case .rhymeDuel: "duel"
        case .addAWord: "sentence"
        case .categories, .longestWord: "round"
        case .wordFootball: "match"
        case .oddOneOut, .fixTheTypo, .speedDefinitions: "game"
        }
    }

    var roundsName: String { self == .wordFootball ? "matches" : roundName + "s" }

    /// Whether the game's rounds are only scored, never won or lost.
    var isScoredOnly: Bool { self == .rhymeDuel || self == .addAWord }
}
