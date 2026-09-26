import Foundation

/// The games behind the controller in the row under the input. A game is the open chat in another mode: every move the
/// model makes is a turn of the chat, so Esc and New Chat forget a game exactly as they forget a question,
/// and nothing about it is written anywhere. Each game's rules live in their own type. `ChatSession` asks
/// them where the game stands, what a line typed into the input does, and what to make of a reply.
nonisolated enum Game: String, CaseIterable, Identifiable, Sendable {
    case rhymeDuel
    case addAWord
    case categories
    case wordFootball
    case oddOneOut
    case fixTheTypo

    var id: Self { self }

    var rules: any GameRules.Type {
        switch self {
        case .rhymeDuel: RhymeDuel.self
        case .addAWord: AddAWord.self
        case .categories: Categories.self
        case .wordFootball: WordFootball.self
        case .oddOneOut: OddOneOut.self
        case .fixTheTypo: FixTheTypo.self
        }
    }

    var title: String { rules.title }
    var summary: String { rules.summary }
    var symbol: String { rules.symbol }

    static let noImages = "Images sit this one out. Just type."
}

/// What `ChatSession` needs from a game. Everything is worked out from the chat's turns, so a game keeps no
/// state of its own: a turn's `cue` is what the model was asked when it moved on its own, its `question`
/// what you typed, its answer the model's reply once judged, and its `outcome` how a move settled on this Mac.
nonisolated protocol GameRules {
    static var title: String { get }
    /// The tooltip of the game's button.
    static var summary: String { get }
    static var symbol: String { get }
    /// Replaces the prompt from Settings for the game's requests, and only for those.
    static var systemPrompt: String { get }
    /// The nudge while the model makes the first move.
    static var invitation: String { get }

    /// Where the game stands.
    static func state(of turns: [ChatSession.Turn]) -> GameState
    /// What a line typed on your move does. `insisting` is true when the same line came back last time
    /// and was sent again unchanged.
    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove
    /// What to make of the model's complete reply to the last turn.
    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply
    /// The transcript the panel shows. A reply still arriving is left out.
    static func lines(for turns: [ChatSession.Turn]) -> [GameLine]
    /// Plain text for Copy.
    static func transcript(of turns: [ChatSession.Turn]) -> String?
    /// A few words for Recent Chats, after the title.
    static func headline(of turns: [ChatSession.Turn]) -> String?
}

nonisolated extension GameRules {
    static func headline(of turns: [ChatSession.Turn]) -> String? { nil }
}

nonisolated struct GameState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// The model moves next, asked with `cue`. The session asks at once when a move of yours or the
        /// start of the game gets here; after a failure, Return asks again.
        case modelMoves(cue: String)
        /// The model is moving.
        case waiting
        /// Your move. `choices` show as buttons that play themselves; Hint shows one of `hints` at a time.
        case yourMove(placeholder: String, choices: [String] = [], hints: [String] = [])
        /// The round is over, and Return starts the next one.
        case over(summary: String, rematch: Rematch)
    }

    var phase: Phase
    /// The footer's count.
    var status: String

    var isYourMove: Bool {
        if case .yourMove = phase { true } else { false }
    }

    var choices: [String] {
        if case .yourMove(_, let choices, _) = phase { choices } else { [] }
    }

    var hints: [String] {
        if case .yourMove(_, _, let hints) = phase { hints } else { [] }
    }
}

nonisolated struct Rematch: Equatable, Sendable {
    /// What the model is asked to start the next round.
    let cue: String
    let placeholder: String
}

nonisolated enum GameMove: Equatable, Sendable {
    /// The line comes back to the input with a nudge, and nothing is sent.
    case reject(String)
    /// The line goes to the model, which replies with its move.
    case ask(String)
    /// The line becomes a finished turn, and nothing is sent: a last word, or giving up.
    case record(String, outcome: GameOutcome?)
    /// The line settles the round on this Mac: the last turn gets the outcome, and nothing is sent.
    case settle(GameOutcome)
}

nonisolated enum GameReply: Equatable, Sendable {
    /// The reply stands, tidied up as the game keeps it.
    case accept(String)
    /// The reply sends the move back: the turn goes, what was typed returns to the input, and a nudge says why.
    case refuse(String)
}

nonisolated struct GameOutcome: Equatable, Sendable {
    let text: String
    /// Whether the round went your way; nil when nobody won it.
    let youWon: Bool?
}

/// One line of a game's transcript.
nonisolated struct GameLine: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading
        case verse
        case verdict(youWon: Bool?)
        case note
    }

    enum Voice: Equatable, Sendable {
        case you
        case model
        case plain
    }

    struct Piece: Equatable, Sendable {
        var text: String
        var voice: Voice
        /// The word the round turned on, such as the typo or the odd one out.
        var isMarked = false
    }

    let id: Int
    let kind: Kind
    let pieces: [Piece]

    var text: String { pieces.map(\.text).joined() }
}

/// Builds a transcript one line at a time.
nonisolated struct GameLines {
    private(set) var all: [GameLine] = []

    mutating func add(_ kind: GameLine.Kind, _ pieces: [GameLine.Piece]) {
        guard pieces.contains(where: { !$0.text.isEmpty }) else { return }
        all.append(GameLine(id: all.count, kind: kind, pieces: pieces))
    }

    mutating func heading(_ text: String) { add(.heading, [.init(text: text, voice: .plain)]) }
    mutating func note(_ text: String) { add(.note, [.init(text: text, voice: .plain)]) }
    mutating func you(_ text: String) { add(.verse, [.init(text: text, voice: .you)]) }
    mutating func model(_ text: String) { add(.verse, [.init(text: text, voice: .model)]) }
    mutating func verse(_ pieces: [GameLine.Piece]) { add(.verse, pieces) }
    mutating func verdict(_ outcome: GameOutcome) { add(.verdict(youWon: outcome.youWon), [.init(text: outcome.text, voice: .plain)]) }

    /// Words in a row with `separator` between them. A word in `marked` is underlined.
    static func chain(_ words: [(text: String, voice: GameLine.Voice)], separator: String, marked: String? = nil) -> [GameLine.Piece] {
        var pieces: [GameLine.Piece] = []
        for (index, word) in words.enumerated() {
            if index > 0 { pieces.append(.init(text: separator, voice: .plain)) }
            pieces.append(.init(text: word.text, voice: word.voice, isMarked: marked.map { GameText.key($0) == GameText.key(word.text) } ?? false))
        }
        return pieces
    }
}

nonisolated extension ChatSession.Turn {
    /// The model's reply once it has been judged; nil while it is still arriving or when there is none.
    var reply: String? { isComplete && !answer.isEmpty ? answer : nil }
}

nonisolated extension Array where Element == ChatSession.Turn {
    /// The turns from the last one the model was asked with one of `cues`, or nil before the first.
    func since(_ cues: Set<String>) -> [ChatSession.Turn]? {
        guard let start = lastIndex(where: { $0.cue.map(cues.contains) == true }) else { return nil }
        return Array(self[start...])
    }

    /// The turns in rounds, each starting at a turn the model was asked with one of `cues`. Turns before
    /// the first are left out.
    func rounds(_ cues: Set<String>) -> [[ChatSession.Turn]] {
        var rounds: [[ChatSession.Turn]] = []
        for turn in self {
            if turn.cue.map(cues.contains) == true {
                rounds.append([turn])
            } else if !rounds.isEmpty {
                rounds[rounds.count - 1].append(turn)
            }
        }
        return rounds
    }
}

/// Reading what was typed and what models reply.
nonisolated enum GameText {
    static let quotes: Set<Character> = ["\"", "“", "”", "'", "‘", "’", "«", "»"]
    private static let wordWrapping = CharacterSet(charactersIn: "\"“”‘’«»*_`()[]{}")
    private static let endPunctuation = CharacterSet(charactersIn: ".,;:!?…").union(.whitespaces)

    /// The non-empty lines of a text, trimmed.
    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    /// The first non-empty line: games go one line at a time.
    static func firstLine(_ text: String) -> String { lines(text).first ?? "" }

    /// A line without the decoration models add: Markdown emphasis, code ticks, a bullet, wrapping quotes.
    static func unwrapped(_ text: String) -> String {
        var line = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").trimmed
        for bullet in ["- ", "• ", "* "] where line.hasPrefix(bullet) { line = String(line.dropFirst(bullet.count)).trimmed }
        while line.count >= 2, let first = line.first, let last = line.last,
              (quotes.contains(first) && quotes.contains(last)) || (first == "*" && last == "*") || (first == "_" && last == "_") {
            line = String(line.dropFirst().dropLast()).trimmed
        }
        return line
    }

    /// The words of a line, split at spaces, without quotes or Markdown around each. Punctuation at the end stays.
    static func words(_ text: String) -> [String] {
        unwrapped(text).split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: wordWrapping) }
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    /// For comparing: lower case, letters and digits only.
    static func key(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Whether two words or phrases are the same, a plural included: "spoon" and "spoons".
    static func sameWord(_ a: String, _ b: String) -> Bool {
        let a = key(a), b = key(b)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a + "s" == b || b + "s" == a || a + "es" == b || b + "es" == a
    }

    /// Typed to give up a round.
    static func isGivingUp(_ text: String) -> Bool {
        ["pass", "giveup", "igiveup"].contains(key(text))
    }

    static func withoutEndPunctuation(_ text: String) -> String {
        text.trimmingCharacters(in: endPunctuation)
    }

    /// A reason to show on its own: a capital first and a period last.
    static func sentence(_ text: String) -> String {
        var text = text.trimmed
        guard let first = text.first else { return text }
        text = first.uppercased() + text.dropFirst()
        if let last = text.last, !".!?…".contains(last) { text += "." }
        return text
    }

    /// “a”, “b”, or “c”.
    static func list(_ words: [String]) -> String {
        let quoted = words.map { "“\($0)”" }
        guard quoted.count > 2 else { return quoted.joined(separator: " or ") }
        return quoted.dropLast().joined(separator: ", ") + ", or " + quoted[quoted.count - 1]
    }

    /// Splits "shown | hidden" at the first bar.
    static func split(_ text: String, at separator: Character = "|") -> (shown: String, hidden: String?) {
        guard let index = text.firstIndex(of: separator) else { return (text.trimmed, nil) }
        return (String(text[..<index]).trimmed, String(text[text.index(after: index)...]).trimmed)
    }

    /// A judge's reply, "OK: …" or "NO: …", as the verdict and what follows it. The verdict is nil when
    /// the reply has neither, and then its whole first line is the rest.
    static func verdict(of reply: String) -> (accepted: Bool?, rest: String) {
        let lines = lines(reply).map(unwrapped).filter { !$0.isEmpty }
        guard let first = lines.first else { return (nil, "") }
        let lowered = first.lowercased()
        for (word, accepted) in [("okay", true), ("ok", true), ("yes", true), ("no", false)] where lowered.hasPrefix(word) {
            let after = first.dropFirst(word.count)
            if let next = after.first, next.isLetter { continue } // "nothing", "yesterday" are words, not verdicts
            var rest = unwrapped(String(after.drop { " :-–—,.!".contains($0) }))
            if rest.isEmpty, lines.count > 1 { rest = lines[1] }
            return (accepted, rest)
        }
        return (nil, first)
    }
}
