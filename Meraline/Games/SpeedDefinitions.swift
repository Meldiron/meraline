import Foundation

/// Speed definitions: the model shows a word, you define it in ten words or fewer, and the model grades
/// your definition out of ten. Five words a game. The model's own definition travels after a bar in its
/// reply ("serendipity | finding something good without looking for it"), hidden until yours is graded.
nonisolated enum SpeedDefinitions: GameRules {
    static let title = "Speed Definitions"
    static let summary = "Define the model’s word in ten words or fewer"
    static let symbol = "character.book.closed"

    static let roundLimit = 5
    static let wordLimit = 10
    /// A grade this good or better means the definition landed.
    static let passMark = 6

    static let opening = "Give the first word."
    static let nextWord = "Give the next word, a different kind of word from the ones so far."
    static let newGame = "Start a new game with a fresh first word."
    private static let gameCues: Set<String> = [opening, newGame]

    static let systemPrompt = """
    You are playing Speed definitions. When asked for a word, reply on one line with one English word that is \
    fun to define, neither obscure nor too easy, then “ | ” and a dictionary definition of ten words or fewer. \
    For example: serendipity | finding something good without looking for it. Pick a different kind of word \
    every time. When the user defines your word, grade the definition on one line: “N/10”, where 10 means it \
    nails the meaning, then “ — ” and a few friendly words on what it caught or missed. Grade the meaning, not \
    spelling or style: a short definition that nails it deserves a 10. No quotation marks or Markdown.
    """

    static let invitation = "The model shows a word. Define it in ten words or fewer, and it grades you out of 10. Five words a game; pass skips one."

    /// The model's word, and its own definition, hidden until you have played.
    struct Word: Equatable {
        var word: String
        var meaning = ""
    }

    struct Grade: Equatable {
        var score: Int
        var comment = ""

        var landed: Bool { score >= SpeedDefinitions.passMark }
        var text: String { comment.isEmpty ? "\(score)/10" : "\(score)/10 · \(comment)" }
    }

    /// A word and what became of it: your definition and its grade, or the pass that skipped it.
    struct Round: Equatable {
        var word: Word
        var definition: String?
        var grade: Grade?
        var skipped: GameOutcome?

        var isSettled: Bool { grade != nil || skipped != nil }
    }

    /// The word in "serendipity | finding…", "Word: serendipity", "serendipity: finding…", or a word with its
    /// definition on the next line.
    static func word(from reply: String) -> Word? {
        let lines = GameText.lines(reply).map(GameText.unwrapped)
        guard let first = lines.first else { return nil }
        var (shown, hidden) = GameText.split(first)
        if hidden == nil, lines.count > 1 { hidden = lines[1] }
        for separator in [":", " — ", " – ", " - "] {
            guard let range = shown.range(of: separator) else { continue }
            let before = String(shown[..<range.lowerBound]), after = String(shown[range.upperBound...]).trimmed
            if ["word", "yourword", "theword", "thewordis", "nextword"].contains(GameText.key(before)) {
                shown = after
            } else if hidden == nil {
                (shown, hidden) = (before, after)
            }
            break
        }
        let words = GameText.words(shown).map(GameText.withoutEndPunctuation)
        guard (1...3).contains(words.count) else { return nil }
        let meaning = hidden.map { GameText.withoutEndPunctuation(GameText.unwrapped($0)) } ?? ""
        return Word(word: words.joined(separator: " "), meaning: meaning)
    }

    /// The grade in "8/10 — nails the luck part", on whichever line the model put it.
    static func grade(from reply: String) -> Grade? {
        let lines = GameText.lines(reply).map(GameText.unwrapped)
        for (index, line) in lines.enumerated() {
            guard let found = GameText.score(in: line) else { continue }
            var comment = found.comment
            if comment.isEmpty, index + 1 < lines.count { comment = lines[index + 1] }
            return Grade(score: found.score, comment: GameText.withoutEndPunctuation(comment))
        }
        return nil
    }

    /// Replies as the game keeps them, which is also how the model sees them later.
    static func format(_ word: Word) -> String {
        word.meaning.isEmpty ? word.word : "\(word.word) | \(word.meaning)"
    }

    static func format(_ grade: Grade) -> String {
        grade.comment.isEmpty ? "\(grade.score)/10" : "\(grade.score)/10 — \(grade.comment)"
    }

    /// The words of one game, in order.
    static func review(_ game: [ChatSession.Turn]) -> [Round] {
        var rounds: [Round] = []
        for turn in game {
            if turn.cue != nil {
                if let word = turn.reply.flatMap(word(from:)) { rounds.append(Round(word: word)) }
            } else if !rounds.isEmpty {
                let last = rounds.count - 1
                if let outcome = turn.outcome {
                    rounds[last].skipped = outcome
                } else {
                    rounds[last].definition = turn.question
                    rounds[last].grade = turn.reply.flatMap(grade(from:))
                }
            }
        }
        return rounds
    }

    /// Whether a definition leans on the word it defines: "happy" is fine for "happiness", "happiness" is not.
    static func uses(_ word: String, in definition: [String]) -> Bool {
        let target = GameText.key(word)
        return definition.contains { typed in
            GameText.sameWord(typed, word) || (target.count >= 4 && GameText.key(typed).contains(target))
        }
    }

    private static func status(word number: Int, points: Int) -> String {
        "Word \(number) of \(roundLimit) · \(points) \(points == 1 ? "point" : "points")"
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let game = turns.since(gameCues), let last = game.last else {
            return GameState(phase: .modelMoves(cue: opening), status: title)
        }
        let rounds = review(game)
        let points = rounds.compactMap(\.grade?.score).reduce(0, +)
        let number = game.filter { $0.cue != nil }.count
        let current = status(word: number, points: points)
        if !last.isComplete { return GameState(phase: .waiting, status: current) }
        if last.cue != nil, let round = rounds.last, !round.isSettled {
            return GameState(phase: .yourMove(placeholder: "Define “\(round.word.word)” in ten words or fewer…"), status: current)
        }
        if number >= roundLimit {
            let landed = rounds.filter { $0.grade?.landed == true }.count
            let outcome = GameOutcome(
                text: "Game done: \(points) of \(roundLimit * 10) points, and \(landed) of \(roundLimit) definitions landed.",
                youWon: landed * 2 > roundLimit
            )
            return GameState(
                phase: .over(outcome: outcome, rematch: Rematch(cue: newGame, placeholder: "Press Return for a new game…")),
                status: "Game done · \(points) of \(roundLimit * 10)"
            )
        }
        return GameState(phase: .modelMoves(cue: nextWord), status: status(word: number + 1, points: points))
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        guard let round = review(turns.since(gameCues) ?? []).last, !round.isSettled else {
            return .reject("Wait for the word.")
        }
        let line = GameText.firstLine(input)
        if line == "?" || GameText.isGivingUp(line) {
            let meaning = round.word.meaning.isEmpty ? "" : " It means \(round.word.meaning)."
            return .record(line, outcome: GameOutcome(text: "Passed.\(meaning)", youWon: false))
        }
        let words = GameText.words(line)
        guard !words.isEmpty else { return .reject("Define “\(round.word.word)” first.") }
        guard words.count <= wordLimit else {
            return .reject("Ten words at most, and that was \(words.count). Trim it down.")
        }
        if uses(round.word.word, in: words) { return .reject("Define “\(round.word.word)” without using it.") }
        return .ask(line)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        if last.cue != nil {
            guard let word = word(from: reply) else {
                return .refuse("The model’s word came out garbled. Press Return for another.")
            }
            let played = review(turns.since(gameCues) ?? []).map(\.word.word)
            if played.contains(where: { GameText.sameWord($0, word.word) }) {
                return .refuse("The model picked “\(word.word)” again. Press Return for another word.")
            }
            return .accept(format(word))
        }
        guard let grade = grade(from: reply) else {
            return .refuse("The model forgot to grade your definition. Press Return to send it again.")
        }
        return .accept(format(grade))
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (number, game) in turns.rounds(gameCues).enumerated() {
            if number > 0 { lines.note("New game") }
            for (index, round) in review(game).enumerated() {
                lines.heading("Word \(index + 1)")
                // The model's own definition shows once yours is graded or skipped.
                var pieces = [GameLine.Piece(text: round.word.word, voice: .model, isMarked: true)]
                if round.isSettled, !round.word.meaning.isEmpty {
                    pieces.append(.init(text: " · \(round.word.meaning)", voice: .plain))
                }
                lines.verse(pieces)
                if let definition = round.definition { lines.you(definition) }
                if let grade = round.grade {
                    lines.verdict(GameOutcome(text: grade.text, youWon: grade.landed))
                } else if let skipped = round.skipped {
                    lines.verdict(GameOutcome(text: "Passed", youWon: skipped.youWon))
                }
            }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let rounds = turns.rounds(gameCues).flatMap(review).map { round in
            var text = round.word.meaning.isEmpty ? round.word.word : "\(round.word.word): \(round.word.meaning)"
            if let definition = round.definition, let grade = round.grade {
                text += "\nYou: \(definition) (\(grade.text))"
            } else if round.skipped != nil {
                text += "\nYou passed."
            }
            return text
        }
        return rounds.isEmpty ? nil : rounds.joined(separator: "\n\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        turns.first?.reply.flatMap(word(from:))?.word
    }
}
