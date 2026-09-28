import Foundation

/// Fix the typo: a sentence with one misspelled word, five a game, and before each you choose who writes it.
/// Either the model writes it and you type the misspelled word spelled right, or you write it and the model
/// finds the word, and you say whether it did. Each sentence is a turn: the model's has only a cue and its reply,
/// yours your sentence and the model's finding. The model's answer to its own sentence travels after a bar in
/// its reply ("…at the libary. | libary → library"), so your fix is judged on this Mac and the typo stays
/// hidden until then.
nonisolated enum FixTheTypo: GameRules {
    static let title = "Fix the Typo"
    static let summary = "Find the misspelled word and fix it"
    static let symbol = "character.cursor.ibeam"

    static let roundLimit = 5

    static let opening = "Write the first sentence."
    static let nextSentence = "Write the next sentence, on a different topic."
    static let newGame = "Start a new game with a fresh sentence on a different topic."
    /// What goes with a sentence of yours that starts a game.
    static let yourGame = "A new game: the user wrote the sentence below, with one misspelled word for you to find."
    /// What goes with a later sentence of yours.
    static let yourSentence = "The user wrote the next sentence, below, with one misspelled word for you to find."
    private static let gameCues: Set<String> = [opening, newGame, yourGame]

    static let randomButton = "Random Sentence"
    static let foundIt = "It found it"
    static let missedIt = "It missed"
    /// What the model writes when it finds nothing misspelled.
    static let nothingWrong = "NONE"

    static let systemPrompt = """
    You are playing Fix the typo, five sentences a game. Before each sentence the user chooses: you write it \
    and they fix it, or they write it and you find the typo. \
    When asked for a sentence, reply on one line with a natural sentence of eight \
    to fifteen words in which exactly one word is misspelled: swap, drop, or double a letter or two so that it \
    is still recognizable, like “recieve” or “tomorow”. Every other word must be spelled correctly. After the \
    sentence write “ | ”, the misspelled word as it appears, “ → ”, and the correct spelling. For example: \
    We will meet at the libary after lunch. | libary → library. Use a different sentence and topic every time. \
    When the user writes the sentence instead, find its one misspelled word and reply on one line with \
    the word as it appears, “ → ”, and the correct spelling, for example: tomorow → tomorrow. If every word is \
    spelled right, write “NONE”. No quotation marks or Markdown.
    """

    static let invitation = "Type a sentence with one misspelled word for the model to find, or let the model write one for you to fix. Five sentences a game, and you choose before each."

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
        guard let hidden, !sentence.isEmpty, let found = correction(in: hidden),
              let written = GameText.words(sentence).first(where: { GameText.key($0) == GameText.key(found.typo) }) else { return nil }
        return Puzzle(sentence: sentence, typo: GameText.withoutEndPunctuation(written), fix: found.fix)
    }

    /// "libary → library", "“libary” -> “library”.", "The word libary → library", or "libary: library" as the
    /// typo, the word before the arrow, and its fix, the word after.
    static func correction(in text: String) -> (typo: String, fix: String)? {
        guard let arrow = ["→", "->", "=>", "⇒", ":"].lazy.compactMap({ text.range(of: $0) }).first else { return nil }
        let typo = word(GameText.words(String(text[..<arrow.lowerBound])).last ?? "")
        let fix = word(String(text[arrow.upperBound...]))
        guard !typo.isEmpty, !fix.isEmpty, GameText.key(typo) != GameText.key(fix) else { return nil }
        return (typo, fix)
    }

    /// The word in "“libary”." or "library.": letters, with an apostrophe or hyphen inside it.
    private static func word(_ text: String) -> String {
        let letters = (GameText.words(text).first ?? "").filter { $0.isLetter || "'’-".contains($0) }
        return String(letters).trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
    }

    static func format(_ puzzle: Puzzle) -> String {
        "\(puzzle.sentence) | \(puzzle.typo) → \(puzzle.fix)"
    }

    /// Whether you wrote this sentence, and the model looked for its typo. The model's sentences have no question.
    static func isYours(_ turn: ChatSession.Turn) -> Bool {
        !turn.question.isEmpty
    }

    /// Whether a game is under way with sentences still to come: the next one is chosen, not a new game.
    private static func isMidGame(_ turns: [ChatSession.Turn]) -> Bool {
        (turns.since(gameCues)?.count ?? roundLimit) < roundLimit
    }

    /// Left to the model, it writes the next sentence, or the first of a new game.
    static func opener(after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> GameOpener {
        guard !isMidGame(turns) else { return .ask(nextSentence) }
        return .ask(turns.isEmpty ? opening : newGame)
    }

    /// Your sentence is the next one, or starts a new game, for the model to find its typo.
    static func open(with input: String, after turns: [ChatSession.Turn]) -> GameMove {
        guard let sentence = sentence(in: input) else { return .reject(aSentence) }
        return .open(sentence, cue: isMidGame(turns) ? yourSentence : yourGame)
    }

    private static let aSentence = "A sentence of a few words, with one of them misspelled."

    /// The sentence you typed, if it has a few words.
    private static func sentence(in input: String) -> String? {
        let line = GameText.firstLine(input)
        return GameText.words(line).count >= 4 ? line : nil
    }

    /// How a game stands: the model's sentences you fixed and missed, and yours it missed and found.
    struct Score: Equatable {
        var fixed = 0, unfixed = 0
        var fooled = 0, found = 0
        /// Whether the game has sentences of each side, settled or not.
        var hasTheModels = false, hasYours = false

        init(of game: [ChatSession.Turn]) {
            for turn in game {
                let yours = FixTheTypo.isYours(turn)
                if yours { hasYours = true } else { hasTheModels = true }
                guard let outcome = turn.outcome else { continue }
                switch (yours, outcome.youWon == true) {
                case (false, true): fixed += 1
                case (false, false): unfixed += 1
                case (true, true): fooled += 1
                case (true, false): found += 1
                }
            }
        }

        /// The sentences that went your way, fixed or fooling the model.
        var yourPoints: Int { fixed + fooled }
        var modelPoints: Int { unfixed + found }

        /// The footer's count: “2 fixed”, “Model found 1”, or both in a game that has both.
        var count: String {
            [hasTheModels ? "\(fixed) fixed" : nil, hasYours ? "Model found \(found)" : nil].compactMap { $0 }.joined(separator: " · ")
        }

        /// How the game went, once it is over. A game of one side's sentences says it as before.
        var outcome: GameOutcome {
            let won = yourPoints > modelPoints
            let text = switch (hasTheModels, hasYours) {
            case (true, false): "Game done: \(fixed) of \(fixed + unfixed) fixed."
            case (false, true): "Game done: the model found \(found) of \(fooled + found), and missed \(fooled)."
            default: "Game done: you fixed \(fixed) of \(fixed + unfixed), and the model found \(found) of \(fooled + found). \(won ? "You win" : "The model wins") \(max(yourPoints, modelPoints)) to \(min(yourPoints, modelPoints))."
            }
            return GameOutcome(text: text, youWon: won)
        }

        /// The footer once the game is over.
        var summary: String {
            switch (hasTheModels, hasYours) {
            case (true, false): "Game done · \(fixed) of \(fixed + unfixed) fixed"
            case (false, true): "Game done · Model found \(found) of \(fooled + found)"
            default: "Game done · You \(yourPoints) – \(modelPoints) Model"
            }
        }
    }

    /// Between sentences the next one waits for you to choose: type one of yours, or leave it to the model.
    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let game = turns.since(gameCues), let last = game.last else {
            let opening = GameOpening(placeholder: "Type a sentence with one misspelled word, or press Return for a random sentence…", button: randomButton)
            return GameState(phase: .opening(opening), status: title)
        }
        let score = Score(of: game)
        let current = "Sentence \(game.count) of \(roundLimit) · \(score.count)"
        if !last.isComplete { return GameState(phase: .waiting, status: current) }
        if last.outcome == nil {
            guard isYours(last) else { return GameState(phase: .yourMove(placeholder: "The misspelled word, spelled right…"), status: current) }
            return GameState(phase: .yourMove(placeholder: "Did the model find it?", choices: [foundIt, missedIt]), status: current)
        }
        if game.count >= roundLimit {
            let next = GameOpening(placeholder: "Type a sentence with a typo for a new game, or press Return for a random sentence…", button: randomButton)
            return GameState(phase: .over(outcome: score.outcome, next: next), status: score.summary)
        }
        let next = GameOpening(placeholder: "Type your next sentence with a typo, or press Return for a random one…", button: randomButton)
        return GameState(phase: .opening(next), status: "Sentence \(game.count + 1) of \(roundLimit) · \(score.count)")
    }

    /// Your move settles the sentence: your fix of the model's, or whether the model found the typo in yours.
    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let game = turns.since(gameCues) ?? []
        if let last = game.last, isYours(last) {
            switch GameText.judgement(input, yes: foundIt, no: missedIt) {
            case true?: return .settle(GameOutcome(text: "The model found it.", youWon: false))
            case false?: return .settle(GameOutcome(text: "You fooled the model.", youWon: true))
            case nil: return .reject("Did the model find it? Tap “\(foundIt)” or “\(missedIt)”.")
            }
        }
        guard let puzzle = game.last?.reply.flatMap(puzzle(from:)) else {
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
        guard let last = turns.last, !last.question.isEmpty else {
            guard let puzzle = puzzle(from: reply) else {
                return .refuse("The model’s sentence came out garbled. Press Return for another.")
            }
            return .accept(format(puzzle))
        }
        let answer = GameText.unwrapped(GameText.firstLine(reply))
        if GameText.key(answer) == GameText.key(nothingWrong) { return .accept(nothingWrong) }
        guard let found = correction(in: answer) else {
            return .refuse("The model’s answer came out garbled. Press Return to ask again.")
        }
        guard GameText.words(last.question).contains(where: { GameText.key($0) == GameText.key(found.typo) }) else {
            return .refuse("The model named “\(found.typo)”, which isn’t in your sentence. Press Return to ask again.")
        }
        return .accept("\(found.typo) → \(found.fix)")
    }

    /// What the model made of your sentence, in a line.
    static func finding(_ reply: String) -> String {
        guard let found = correction(in: reply) else { return "The model found nothing misspelled." }
        return "The model says “\(found.typo)” should be “\(found.fix)”."
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (number, game) in turns.rounds(gameCues).enumerated() {
            if number > 0 { lines.note("New game") }
            for turn in game {
                if isYours(turn) {
                    lines.you(turn.question)
                    if let reply = turn.reply { lines.model(finding(reply)) }
                    if let outcome = turn.outcome { lines.verdict(outcome) }
                    continue
                }
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
        let rounds = turns.rounds(gameCues).flatMap { game in
            game.compactMap { turn -> String? in
                if isYours(turn) {
                    let found = turn.reply.map { "\n\(finding($0))" } ?? ""
                    return turn.question + found + (turn.outcome.map { "\n\($0.text)" } ?? "")
                }
                guard let puzzle = turn.reply.flatMap(puzzle(from:)) else { return nil }
                return turn.outcome.map { "\(puzzle.sentence)\n\($0.text)" } ?? puzzle.sentence
            }
        }
        return rounds.isEmpty ? nil : rounds.joined(separator: "\n\n")
    }
}

nonisolated extension FixTheTypo {
    /// A game's numbers for Settings › Usage: the model's sentences and the typos you fixed, yours and how many
    /// fooled it.
    static func figures(ofRoundEndingIn turns: [ChatSession.Turn]) -> GameFigures {
        var figures = GameFigures()
        guard let game = turns.since(gameCues) else { return figures }
        let score = Score(of: game)
        figures.add(score.fixed + score.unfixed, to: .theirPuzzles)
        figures.add(score.fixed, to: .fixed)
        figures.add(score.fooled + score.found, to: .yourPuzzles)
        figures.add(score.fooled, to: .fooled)
        return figures
    }
}
