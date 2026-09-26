import Foundation

/// Fix the typo: the model writes a sentence with one misspelled word, and you type the word spelled
/// right. Five sentences a game. The model's answer travels after a bar in its reply ("…at the libary.
/// | libary → library"), so your fix is judged on this Mac and the typo stays hidden until then.
nonisolated enum FixTheTypo: GameRules {
    static let title = "Fix the Typo"
    static let summary = "Find the misspelled word and fix it"
    static let symbol = "character.cursor.ibeam"

    static let roundLimit = 5

    static let opening = "Write the first sentence."
    static let nextSentence = "Write the next sentence, on a different topic."
    static let newGame = "Start a new game with a fresh sentence on a different topic."
    private static let gameCues: Set<String> = [opening, newGame]

    static let systemPrompt = """
    You are playing Fix the typo. When asked for a sentence, reply on one line with a natural sentence of eight \
    to fifteen words in which exactly one word is misspelled: swap, drop, or double a letter or two so that it \
    is still recognizable, like “recieve” or “tomorow”. Every other word must be spelled correctly. After the \
    sentence write “ | ”, the misspelled word as it appears, “ → ”, and the correct spelling. For example: \
    We will meet at the libary after lunch. | libary → library. Use a different sentence and topic every time. \
    No quotation marks or Markdown.
    """

    static let invitation = "The model writes a sentence with one misspelled word. Type that word spelled right, or pass to see it."

    struct Puzzle: Equatable {
        var sentence: String
        var typo: String
        var fix: String
    }

    static func puzzle(from reply: String) -> Puzzle? {
        let lines = GameText.lines(reply).map(GameText.unwrapped)
        guard let first = lines.first else { return nil }
        var (sentence, hidden) = GameText.split(first)
        if hidden == nil, lines.count > 1 { hidden = lines[1] }
        guard let hidden, !sentence.isEmpty else { return nil }
        guard let arrow = ["→", "->", "=>", "⇒", ":"].lazy.compactMap({ hidden.range(of: $0) }).first else { return nil }
        let typo = word(String(hidden[..<arrow.lowerBound]))
        let fix = word(String(hidden[arrow.upperBound...]))
        guard !typo.isEmpty, !fix.isEmpty, GameText.key(typo) != GameText.key(fix),
              let written = GameText.words(sentence).first(where: { GameText.key($0) == GameText.key(typo) }) else { return nil }
        return Puzzle(sentence: sentence, typo: GameText.withoutEndPunctuation(written), fix: fix)
    }

    /// The word in "“libary”." or "library.": letters, with an apostrophe or hyphen inside it.
    private static func word(_ text: String) -> String {
        let letters = (GameText.words(text).first ?? "").filter { $0.isLetter || "'’-".contains($0) }
        return String(letters).trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
    }

    static func format(_ puzzle: Puzzle) -> String {
        "\(puzzle.sentence) | \(puzzle.typo) → \(puzzle.fix)"
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let game = turns.since(gameCues), let last = game.last else {
            return GameState(phase: .modelMoves(cue: opening), status: title)
        }
        let fixed = game.filter { $0.outcome?.youWon == true }.count
        let current = "Sentence \(game.count) of \(roundLimit) · \(fixed) fixed"
        if !last.isComplete { return GameState(phase: .waiting, status: current) }
        if last.outcome == nil { return GameState(phase: .yourMove(placeholder: "The misspelled word, spelled right…"), status: current) }
        if game.count >= roundLimit {
            return GameState(
                phase: .over(summary: "Game done: \(fixed) of \(roundLimit) fixed. Press Return for a new game.", rematch: Rematch(cue: newGame, placeholder: "Press Return for a new game…")),
                status: "Game done · \(fixed) of \(roundLimit) fixed"
            )
        }
        return GameState(phase: .modelMoves(cue: nextSentence), status: "Sentence \(game.count + 1) of \(roundLimit) · \(fixed) fixed")
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        guard let puzzle = turns.since(gameCues)?.last?.reply.flatMap(puzzle(from:)) else {
            return .reject("Wait for the sentence.")
        }
        let typed = input.trimmed
        if typed == "?" || GameText.isGivingUp(typed) {
            return .settle(GameOutcome(text: "It was “\(puzzle.typo)”, spelled “\(puzzle.fix)”.", youWon: false))
        }
        let keys = GameText.words(typed).map(GameText.key)
        if keys.contains(GameText.key(puzzle.fix)) {
            return .settle(GameOutcome(text: "Fixed: “\(puzzle.typo)” is “\(puzzle.fix)”.", youWon: true))
        }
        if keys == [GameText.key(puzzle.typo)] { return .reject("Found it! Now type it spelled right.") }
        return .reject("Not quite. Look again, or type pass to see it.")
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let puzzle = puzzle(from: reply) else {
            return .refuse("The model’s sentence came out garbled. Press Return for another.")
        }
        return .accept(format(puzzle))
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (number, game) in turns.rounds(gameCues).enumerated() {
            if number > 0 { lines.note("New game") }
            for turn in game {
                guard let puzzle = turn.reply.flatMap(puzzle(from:)) else { continue }
                guard let outcome = turn.outcome else {
                    lines.model(puzzle.sentence)
                    continue
                }
                var marked = false
                let pieces = puzzle.sentence.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { index, token in
                    let isTypo = !marked && GameText.key(String(token)) == GameText.key(puzzle.typo)
                    if isTypo { marked = true }
                    return GameLine.Piece(text: (index == 0 ? "" : " ") + token, voice: .model, isMarked: isTypo)
                }
                lines.verse(pieces)
                lines.verdict(outcome)
            }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let rounds = turns.rounds(gameCues).flatMap { $0 }.compactMap { turn -> String? in
            guard let puzzle = turn.reply.flatMap(puzzle(from:)) else { return nil }
            return turn.outcome.map { "\(puzzle.sentence)\n\($0.text)" } ?? puzzle.sentence
        }
        return rounds.isEmpty ? nil : rounds.joined(separator: "\n\n")
    }
}
