import Foundation

/// Odd one out: rounds alternate, started by you or the model. The model sets three words and you tap the one
/// that doesn't belong; you set three and the model picks, and you say whether it got it. Three rounds each.
///
/// The model's own answer travels after a bar in its reply ("apple · hammer · banana | hammer: not a
/// fruit"), so your pick is judged on this Mac and the answer stays hidden until you have picked.
///
/// Each of the model's puzzles gets a theme and a way to link the two that belong, drawn on this Mac: left to
/// itself, the model sets fruit and a hammer every game.
nonisolated enum OddOneOut: GameRules {
    static let title = "Odd One Out"
    static let summary = "Spot the word that doesn’t belong, then set one"
    static let symbol = "rectangle.3.group"

    static let roundLimit = 6

    static let opening = "Set the first puzzle."
    static let nextPuzzle = "Set the next puzzle, different from the ones so far."
    static let newGame = "Start a new game: set a first puzzle unlike the ones so far."
    /// What goes with your three words when they start a game.
    static let yourGame = "The user starts this game by setting the first puzzle, below."
    private static let gameCues: Set<String> = [opening, newGame, yourGame]
    /// The cues the model sets a puzzle with.
    private static let puzzleCues: Set<String> = [opening, nextPuzzle, newGame]

    static let randomButton = "Random Puzzle"

    static let gotIt = "It got it"
    static let missedIt = "It missed"

    static let systemPrompt = """
    You are playing Odd one out. When asked to set a puzzle, reply on one line with three words, two that \
    belong together and one that doesn't, in random order and separated by “ · ”, then “ | ”, then the odd one \
    out, a colon, and a few words on why. For example: apple · hammer · banana | hammer: not a fruit. \
    Build it around the theme the message gives, linking the two that belong the way it suggests if that makes a \
    fair puzzle. Make it clever but fair, and unlike the puzzles so far. \
    When the user gives you three words, reply on one line with the one you think doesn't belong, a colon, and \
    a few words on why. For example: piano: not a fruit. No quotation marks or Markdown.
    """

    static let invitation = "Set three words for the model, one that doesn’t belong, or let it set the first puzzle. Then take turns, three rounds each."

    struct Puzzle: Equatable {
        var options: [String]
        var answer: String
        var reason: String
    }

    struct Pick: Equatable {
        var word: String
        var reason: String
    }

    static func puzzle(from reply: String) -> Puzzle? {
        let lines = GameText.lines(reply).map(GameText.unwrapped)
        guard let first = lines.first else { return nil }
        var (shown, hidden) = GameText.split(first)
        if hidden == nil, lines.count > 1 { hidden = lines[1] }
        let options = words(in: shown)
        guard options.count == 3, Set(options.map(GameText.key)).count == 3, let hidden else { return nil }
        let (answerText, reason) = splitReason(hidden)
        guard let answer = match(answerText, in: options) else { return nil }
        return Puzzle(options: options, answer: answer, reason: reason)
    }

    static func pick(from reply: String, options: [String]) -> Pick? {
        let line = GameText.unwrapped(GameText.firstLine(reply))
        let (pickText, reason) = splitReason(line)
        guard let word = match(pickText, in: options) ?? match(line, in: options) else { return nil }
        return Pick(word: word, reason: reason)
    }

    /// Three words from "a · b · c", "a, b, c", "a, b and c", or "a b c".
    static func words(in text: String) -> [String] {
        let separators: Set<Character> = ["·", "•", ",", "/", ";", "|"]
        var parts = text.replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: " or ", with: ",")
            .split { separators.contains($0) }
            .map { clean(String($0)) }
            .filter { !$0.isEmpty }
        if parts.count == 1 { parts = GameText.words(text).map { clean($0) }.filter { !$0.isEmpty } }
        return parts
    }

    /// A word without list numbering or punctuation around it.
    private static func clean(_ text: String) -> String {
        var word = GameText.unwrapped(text)
        if let numbering = word.firstMatch(of: #/^(?:\d+|[a-c])[.)]\s+/#) { word.removeSubrange(numbering.range) }
        return GameText.withoutEndPunctuation(GameText.unwrapped(word))
    }

    /// "hammer: not a fruit" as "hammer" and "not a fruit".
    private static func splitReason(_ text: String) -> (String, String) {
        for separator in [":", " — ", " – ", " - ", " because "] {
            if let range = text.range(of: separator) {
                return (String(text[..<range.lowerBound]).trimmed, GameText.withoutEndPunctuation(String(text[range.upperBound...])))
            }
        }
        return (text.trimmed, "")
    }

    /// The option `text` names: the same word, or the longest option inside it ("the hammer").
    private static func match(_ text: String, in options: [String]) -> String? {
        let key = GameText.key(text)
        guard !key.isEmpty else { return nil }
        if let exact = options.first(where: { GameText.sameWord($0, text) }) { return exact }
        return options.filter { key.contains(GameText.key($0)) }.max { GameText.key($0).count < GameText.key($1).count }
    }

    /// Which option you picked: by name, the start of one, or its number.
    static func choose(_ input: String, from options: [String]) -> String? {
        let key = GameText.key(input)
        guard !key.isEmpty else { return nil }
        if let number = Int(key), (1...options.count).contains(number) { return options[number - 1] }
        if let exact = options.first(where: { GameText.sameWord($0, input) }) { return exact }
        let starting = options.filter { GameText.key($0).hasPrefix(key) }
        return starting.count == 1 ? starting[0] : nil
    }

    /// Whether you said the model got your puzzle.
    static func judgement(_ input: String) -> Bool? {
        GameText.judgement(input, yes: gotIt, no: missedIt)
    }

    static func format(_ puzzle: Puzzle) -> String {
        "\(puzzle.options.joined(separator: " · ")) | \(puzzle.answer): \(puzzle.reason)"
    }

    private static func score(of game: [ChatSession.Turn]) -> (you: Int, model: Int) {
        (game.filter { $0.outcome?.youWon == true }.count, game.filter { $0.outcome?.youWon == false }.count)
    }

    /// A puzzle of the model's gets a theme, one the chat hasn't had while others are left, and a way to link the
    /// two that belong.
    static func aside(for turn: ChatSession.Turn, after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> String? {
        guard turn.cue.map(puzzleCues.contains) == true else { return nil }
        let asides = turns.compactMap(\.aside)
        guard let theme = dice.pick(from: themes, preferring: { theme in !asides.contains { $0.hasPrefix(themed(theme)) } }) else { return nil }
        let link = links.randomElement(using: &dice) ?? links[0]
        return "\(themed(theme)) Link the two that belong by \(link)."
    }

    private static func themed(_ theme: String) -> String {
        "This puzzle’s theme: \(theme)."
    }

    /// What a puzzle of the model's is about.
    static let themes = [
        "food", "animals", "music", "sport", "space", "the ocean", "weather", "geography", "history", "science",
        "the human body", "cooking", "colors", "jobs", "transport", "clothing", "myths and legends", "fairy tales",
        "the kitchen", "the garden", "the farm", "school", "the office", "travel", "holidays", "games", "toys",
        "birds", "insects", "trees", "flowers", "fruit", "vegetables", "cheese", "bread", "drinks", "desserts",
        "spices", "gemstones", "metals", "musical instruments", "dances", "films", "books", "the alphabet",
        "numbers", "shapes", "time", "money", "tools", "furniture", "rivers and seas", "mountains", "cities",
        "countries", "languages", "planets", "dinosaurs", "reptiles", "fish", "dogs", "horses", "chess",
        "playing cards", "the beach", "camping", "winter", "summer", "the circus", "castles", "pirates", "robots",
        "computers", "cars", "trains", "boats", "aircraft", "buildings", "bridges", "sweets", "breakfast",
        "coffee and tea", "pasta", "sauces", "herbs", "art", "the theater", "the post office", "the moon"
    ]

    /// Ways to link the two that belong: “Link the two that belong by …”.
    static let links = [
        "what they are", "what they are made of", "where they come from", "what they are used for",
        "how they are spelled", "their color", "their size", "a word hidden inside them", "the sound they make",
        "where you find them", "how they move", "when you use them"
    ]

    /// Whether the turn is a puzzle the model set.
    private static func isModels(_ turn: ChatSession.Turn) -> Bool {
        turn.cue.map(puzzleCues.contains) == true
    }

    /// Left to the model, it sets the game's first puzzle.
    static func opener(after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> GameOpener {
        .ask(turns.isEmpty ? opening : newGame)
    }

    /// Your three words start the game.
    static func open(with input: String, after turns: [ChatSession.Turn]) -> GameMove {
        guard let words = three(in: input) else { return .reject(threeWords) }
        return .open(words, cue: yourGame)
    }

    private static let threeWords = "Three different words, one that doesn’t belong, separated by commas."

    /// Three different words from what you typed, as the model is sent them.
    private static func three(in input: String) -> String? {
        let words = words(in: GameText.firstLine(input))
        guard words.count == 3, Set(words.map(GameText.key)).count == 3 else { return nil }
        return words.joined(separator: ", ")
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let game = turns.since(gameCues), let last = game.last else {
            let opening = GameOpening(placeholder: "Set three words, one that doesn’t belong, or press Return for a random puzzle…", button: randomButton)
            return GameState(phase: .opening(opening), status: title)
        }
        let score = score(of: game)
        let tally = "You \(score.you), Model \(score.model)"
        let current = "Round \(game.count) of \(roundLimit) · \(tally)"
        if !last.isComplete { return GameState(phase: .waiting, status: current) }
        if last.outcome == nil {
            if isModels(last), let puzzle = last.reply.flatMap(puzzle(from:)) {
                return GameState(phase: .yourMove(placeholder: "Tap the odd one out, or type it…", choices: puzzle.options), status: current)
            }
            if !isModels(last) {
                return GameState(phase: .yourMove(placeholder: "Did the model get it?", choices: [gotIt, missedIt]), status: current)
            }
        }
        if game.count >= roundLimit {
            let outcome: GameOutcome
            if score.you > score.model {
                outcome = GameOutcome(text: "Game done: you win, \(score.you) to \(score.model).", youWon: true)
            } else if score.you < score.model {
                outcome = GameOutcome(text: "Game done: the model wins, \(score.model) to \(score.you).", youWon: false)
            } else {
                outcome = GameOutcome(text: "Game done: a draw, \(score.you) all.", youWon: nil)
            }
            return GameState(
                phase: .over(outcome: outcome, next: GameOpening(placeholder: "Set three words for a new game, or press Return for a random puzzle…", button: randomButton)),
                status: "Game done · \(tally)"
            )
        }
        let next = "Round \(game.count + 1) of \(roundLimit) · \(tally)"
        // Whoever set the first puzzle sets every other one.
        if game.count.isMultiple(of: 2) == isModels(game[0]) { return GameState(phase: .modelMoves(cue: nextPuzzle), status: next) }
        return GameState(phase: .yourMove(placeholder: "Your three words, one that doesn’t belong…"), status: next)
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        if let last = turns.since(gameCues)?.last, last.isComplete, last.outcome == nil {
            if isModels(last), let puzzle = last.reply.flatMap(puzzle(from:)) {
                guard let choice = choose(input, from: puzzle.options) else {
                    return .reject("Pick one of the three: \(GameText.list(puzzle.options)).")
                }
                let why = puzzle.reason.isEmpty ? "" : ": \(puzzle.reason)"
                return choice == puzzle.answer
                    ? .settle(GameOutcome(text: "Right, “\(choice)”\(why).", youWon: true))
                    : .settle(GameOutcome(text: "Not “\(choice)”. It was “\(puzzle.answer)”\(why).", youWon: false))
            }
            if !isModels(last) {
                switch judgement(input) {
                case true?: return .settle(GameOutcome(text: "The model got it.", youWon: false))
                case false?: return .settle(GameOutcome(text: "You fooled the model.", youWon: true))
                case nil: return .reject("Did the model get it? Tap “\(gotIt)” or “\(missedIt)”.")
                }
            }
        }
        guard let words = three(in: input) else { return .reject(threeWords) }
        return .ask(words)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        if isModels(last) {
            guard let puzzle = puzzle(from: reply) else {
                return .refuse("The model’s puzzle came out garbled. Press Return for another.")
            }
            return .accept(format(puzzle))
        }
        guard let pick = pick(from: reply, options: words(in: last.question)) else {
            return .refuse("The model picked something that wasn’t there. Press Return to ask again.")
        }
        return .accept(pick.reason.isEmpty ? pick.word : "\(pick.word): \(pick.reason)")
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (number, game) in turns.rounds(gameCues).enumerated() {
            if number > 0 { lines.note("New game") }
            for (index, turn) in game.enumerated() {
                if isModels(turn) {
                    lines.heading("Round \(index + 1) · the model’s three")
                    // While you pick, the three words are the buttons under the transcript.
                    guard let outcome = turn.outcome, let puzzle = turn.reply.flatMap(puzzle(from:)) else { continue }
                    lines.verse(GameLines.chain(puzzle.options.map { ($0, .model) }, separator: " · ", marked: puzzle.answer))
                    lines.verdict(outcome)
                } else {
                    lines.heading("Round \(index + 1) · your three")
                    lines.you(words(in: turn.question).joined(separator: " · "))
                    if let reply = turn.reply { lines.model("The model picks \(reply)") }
                    if let outcome = turn.outcome { lines.verdict(outcome) }
                }
            }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        var text: [String] = []
        for game in turns.rounds(gameCues) {
            for (index, turn) in game.enumerated() {
                guard let outcome = turn.outcome else { continue }
                if isModels(turn), let puzzle = turn.reply.flatMap(puzzle(from:)) {
                    text.append("Round \(index + 1), the model’s three: \(puzzle.options.joined(separator: " · ")). \(outcome.text)")
                } else if !isModels(turn) {
                    text.append("Round \(index + 1), your three: \(words(in: turn.question).joined(separator: " · ")). The model picked \(turn.reply ?? "nothing"). \(outcome.text)")
                }
            }
        }
        return text.isEmpty ? nil : text.joined(separator: "\n")
    }
}

nonisolated extension OddOneOut {
    /// A game's numbers for Settings › Usage: the model's puzzles and how many you spotted, yours and how many
    /// fooled it.
    static func figures(ofRoundEndingIn turns: [ChatSession.Turn]) -> GameFigures {
        var figures = GameFigures()
        for turn in turns.since(gameCues) ?? [] {
            guard let outcome = turn.outcome else { continue }
            let won = outcome.youWon == true ? 1 : 0
            if isModels(turn) {
                figures.add(1, to: .theirPuzzles)
                figures.add(won, to: .spotted)
            } else {
                figures.add(1, to: .yourPuzzles)
                figures.add(won, to: .fooled)
            }
        }
        return figures
    }
}
