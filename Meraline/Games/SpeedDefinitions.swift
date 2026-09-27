import Foundation

/// Speed definitions: five words a game, from one side for the whole game. Either the model shows a word, you
/// define it in ten words or fewer, and the model grades your definition out of ten, or you give the words, the
/// model defines each, and you say whether it got it. The model's own definition of its word travels after a
/// bar in its reply ("serendipity | finding something good without looking for it"), hidden until yours is
/// graded.
///
/// The model picks each word from three dealt on this Mac, of a difficulty drawn there too (`Difficulty`):
/// left to itself, it opens with serendipity every game, and its words run hard.
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
    /// What goes with your first word: you give the words this game.
    static let yourGame = "The user gives the words this game: define each in ten words or fewer, without using it. Here is the first."
    private static let gameCues: Set<String> = [opening, newGame, yourGame]
    /// The cues the model shows a word with.
    private static let wordCues: Set<String> = [opening, nextWord, newGame]

    static let randomButton = "Random Word"
    static let gotIt = "It got it"
    static let missedIt = "It missed"

    static let systemPrompt = """
    You are playing Speed definitions. When asked for a word, reply on one line with one of the words the message \
    offers, or, when it offers none, one English word that is fun to define, most often of medium difficulty; then \
    “ | ” and a dictionary definition of ten words or fewer. For example: serendipity | finding something good \
    without looking for it. Never give a word played already. When the user defines your word, grade the \
    definition on one line: “N/10”, where 10 means it nails the meaning, then “ — ” and a few friendly words on \
    what it caught or missed. Grade the meaning, not spelling or style: a short definition that nails it deserves \
    a 10. When the user gives the words instead, define each one on one line in ten words or fewer, without \
    using the word itself. No quotation marks or Markdown.
    """

    static let invitation = "Type a word for the model to define, or take a random one to define yourself in ten words or fewer. Five words a game; pass skips one."

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
        var difficulty: Difficulty?
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
                if let word = turn.reply.flatMap(word(from:)) { rounds.append(Round(word: word, difficulty: Difficulty(of: turn))) }
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

    /// A new word gets three to pick from, all of one difficulty, none the chat has played while there are others.
    static func aside(for turn: ChatSession.Turn, after turns: [ChatSession.Turn], dice: inout GameDice) -> String? {
        guard turn.cue.map(wordCues.contains) == true else { return nil }
        return offer(Difficulty.draw(dice: &dice), after: turns, dice: &dice)
    }

    /// Three words of `difficulty` for the model to pick from.
    static func offer(_ difficulty: Difficulty, after turns: [ChatSession.Turn], dice: inout GameDice) -> String {
        let played = Set(turns.rounds(gameCues).flatMap(words(of:)).map(GameText.key))
        let offered = dice.deal(offeredCount, from: difficulty.words) { !played.contains(GameText.key($0)) }
        return "Pick one of these words, all of \(difficulty.rawValue) difficulty: \(GameText.list(offered))."
    }

    /// How many words the model picks from.
    static let offeredCount = 3

    /// How hard a word is to define. Most words are medium; one in five is easy, and one in five hard.
    enum Difficulty: String, CaseIterable {
        case easy, medium, hard

        /// A difficulty at random, medium three times as often as either of the others.
        static func draw(dice: inout GameDice) -> Difficulty {
            switch Int.random(in: 0..<5, using: &dice) {
            case 0: .easy
            case 4: .hard
            default: .medium
            }
        }

        /// The difficulty a turn's word was drawn at, from its aside.
        init?(of turn: ChatSession.Turn) {
            guard let aside = turn.aside,
                  let found = Difficulty.allCases.first(where: { aside.contains("all of \($0.rawValue) difficulty") }) else { return nil }
            self = found
        }

        var words: [String] {
            switch self {
            case .easy: SpeedDefinitions.easyWords
            case .medium: SpeedDefinitions.mediumWords
            case .hard: SpeedDefinitions.hardWords
            }
        }
    }

    /// Everyday words, quick to pin down.
    static let easyWords = [
        "umbrella", "breakfast", "ladder", "pillow", "whisper", "puzzle", "shadow", "rainbow", "blanket", "bicycle",
        "candle", "compass", "envelope", "giggle", "hammock", "helmet", "island", "jacket", "kettle", "lantern",
        "magnet", "mirror", "parachute", "pocket", "recipe", "sandwich", "scissors", "snore", "sneeze", "telescope",
        "tickle", "toothbrush", "tunnel", "volcano", "wallet", "yawn", "zipper", "balloon", "bridge", "fountain",
        "glove", "hiccup", "honey", "iceberg", "jigsaw", "keyboard", "library", "marathon", "necklace", "passport",
        "picnic", "quilt", "robot", "skeleton", "souvenir", "stapler", "suitcase", "thermometer", "trophy", "vacuum",
        "waterfall", "wink", "doodle", "drizzle", "bargain", "gossip", "shrug", "snooze", "maze", "riddle", "cozy",
        "clumsy", "habit", "homesick", "prank", "pun", "nap", "echo", "tantrum", "errand", "detour", "confetti",
        "lullaby", "fidget", "wobble", "mumble", "recycle", "blizzard"
    ]

    /// Words most people know but few define in ten words without a think.
    static let mediumWords = [
        "ambition", "anecdote", "anonymous", "apology", "appetite", "avalanche", "awkward", "bluff", "boredom",
        "boycott", "brainstorm", "bribe", "budget", "camouflage", "candid", "caution", "celebrity", "chaos",
        "charisma", "coincidence", "commute", "compromise", "conscience", "cringe", "curfew", "curiosity", "deadline",
        "debut", "dilemma", "diplomat", "disguise", "eavesdrop", "eclipse", "eccentric", "elegant", "embarrass",
        "encore", "envy", "etiquette", "evidence", "exaggerate", "excuse", "expedition", "fad", "fatigue", "fiasco",
        "flattery", "fluke", "folklore", "forecast", "frugal", "fumble", "gadget", "gibberish", "gimmick", "glitch",
        "gourmet", "gratitude", "grudge", "gullible", "haggle", "harmony", "hindsight", "hoax", "horizon", "humble",
        "hunch", "idle", "illusion", "impatient", "improvise", "impulse", "inkling", "insomnia", "intuition",
        "jargon", "jealousy", "jinx", "karma", "keepsake", "landmark", "legacy", "leisure", "luxury", "meander",
        "memoir", "mentor", "mirage", "mischief", "momentum", "monologue", "myth", "naive", "negotiate", "nemesis",
        "nitpick", "nomad", "nonsense", "nostalgia", "novice", "oasis", "oblivious", "obstacle", "omen", "optimist",
        "outlier", "paranoid", "patience", "peckish", "perfectionist", "persuade", "placebo", "ponder",
        "procrastinate", "prodigy", "prophecy", "quarantine", "quirk", "ransom", "rebel", "refuge", "regret",
        "rehearse", "relic", "remedy", "reunion", "ritual", "rumor", "sabotage", "sarcasm", "scapegoat", "scavenger",
        "scheme", "siesta", "silhouette", "skeptic", "slogan", "smug", "spontaneous", "squabble", "stalemate",
        "stamina", "stealth", "stubborn", "superstition", "suspense", "sympathy", "taboo", "tangent", "tedious",
        "temptation", "thrifty", "tradition", "tranquil", "trivia", "tsunami", "tycoon", "ultimatum", "vague", "veto",
        "vintage", "virtue", "vivid", "wanderlust", "whim", "wisdom", "witness", "yearn", "loophole", "mediocre",
        "overwhelm", "quibble", "resilient", "sheepish", "catastrophe", "bureaucracy", "empathy", "alibi", "jackpot",
        "sidekick", "hoard", "fanatic", "gridlock", "mascot", "nickname", "hermit", "bystander"
    ]

    /// Words that take some knowing.
    static let hardWords = [
        "ambiguous", "benevolent", "enigma", "epiphany", "euphoria", "hypothesis", "inertia", "itinerary",
        "jubilant", "labyrinth", "melancholy", "nuance", "oracle", "paradox", "plagiarism", "pseudonym",
        "serendipity", "understatement", "utopia", "velocity", "zeal", "zenith", "ephemeral", "gregarious",
        "petrichor", "ubiquitous", "cacophony", "juggernaut", "trepidation", "ambivalent", "altruism", "aplomb",
        "cajole", "candor", "conundrum", "debacle", "deference", "dichotomy", "eloquent", "esoteric", "facetious",
        "frivolous", "gaffe", "hubris", "idiosyncrasy", "impetuous", "incognito", "indelible", "lethargy",
        "loquacious", "magnanimous", "meticulous", "nebulous", "nonchalant", "obsequious", "onomatopoeia", "panacea",
        "paraphernalia", "pragmatic", "precocious", "quintessential", "rhetoric", "sanguine", "solace", "sycophant",
        "tenacious", "verbose", "vicarious", "whimsical", "zeitgeist", "ennui", "halcyon", "ineffable", "mellifluous",
        "oxymoron", "palindrome", "quixotic", "surreptitious", "taciturn", "wistful"
    ]

    private static func status(word number: Int, points: Int) -> String {
        "Word \(number) of \(roundLimit) · \(points) \(points == 1 ? "point" : "points")"
    }

    /// Whether you give the words this game, and the model defines them.
    static func youGive(_ game: [ChatSession.Turn]) -> Bool {
        game.first?.cue == yourGame
    }

    /// The words a game played, the model's or yours.
    private static func words(of game: [ChatSession.Turn]) -> [String] {
        youGive(game) ? game.map(\.question) : review(game).map(\.word.word)
    }

    /// Left to the model, it shows the game's words, from those drawn on this Mac.
    static func opener(after turns: [ChatSession.Turn], dice: inout GameDice) -> GameOpener {
        .ask(turns.isEmpty ? opening : newGame)
    }

    /// Your word starts a game in which you give them all.
    static func open(with input: String, after turns: [ChatSession.Turn]) -> GameMove {
        give(input, after: []) { .open($0, cue: yourGame) }
    }

    /// A word you typed for the model to define, made into `move`, or why it can't be one.
    private static func give(_ input: String, after game: [ChatSession.Turn], as move: (String) -> GameMove) -> GameMove {
        let words = GameText.words(GameText.firstLine(input)).map(GameText.withoutEndPunctuation)
        guard (1...3).contains(words.count), !GameText.isGivingUp(words[0]) else {
            return .reject("One word, or a short phrase, for the model to define.")
        }
        let word = words.joined(separator: " ")
        if game.contains(where: { GameText.sameWord($0.question, word) }) { return .reject("“\(word)” was played already. Try another.") }
        return move(word)
    }

    /// The model's definition of your word, without the word or a label before it.
    static func definition(from reply: String, of word: String) -> String {
        var line = GameText.unwrapped(GameText.firstLine(reply))
        let (shown, hidden) = GameText.split(line)
        if let hidden, GameText.key(shown) == GameText.key(word) { line = hidden }
        for separator in [":", " — ", " – ", " - "] {
            guard let range = line.range(of: separator) else { continue }
            let before = GameText.key(String(line[..<range.lowerBound]))
            if [GameText.key(word), "definition", "meaning"].contains(before) { line = String(line[range.upperBound...]).trimmed }
            break
        }
        return GameText.withoutEndPunctuation(GameText.unwrapped(line))
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let game = turns.since(gameCues), let last = game.last else {
            let opening = GameOpening(placeholder: "Type a word for the model to define, or press Return for a random one…", button: randomButton)
            return GameState(phase: .opening(opening), status: title)
        }
        let next = GameOpening(placeholder: "Type a word for a new game, or press Return for a random one…", button: randomButton)
        if youGive(game) { return stateOfYourWords(game, last: last, next: next) }
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
            return GameState(phase: .over(outcome: outcome, next: next), status: "Game done · \(points) of \(roundLimit * 10)")
        }
        return GameState(phase: .modelMoves(cue: nextWord), status: status(word: number + 1, points: points))
    }

    private static func stateOfYourWords(_ game: [ChatSession.Turn], last: ChatSession.Turn, next: GameOpening) -> GameState {
        let got = game.filter { $0.outcome?.youWon == false }.count
        let current = "Word \(game.count) of \(roundLimit) · Model got \(got)"
        if !last.isComplete { return GameState(phase: .waiting, status: current) }
        if last.outcome == nil { return GameState(phase: .yourMove(placeholder: "Did the model get it?", choices: [gotIt, missedIt]), status: current) }
        if game.count >= roundLimit {
            let missed = roundLimit - got
            let outcome = GameOutcome(text: "Game done: the model got \(got) of \(roundLimit), and missed \(missed).", youWon: missed * 2 > roundLimit)
            return GameState(phase: .over(outcome: outcome, next: next), status: "Game done · Model got \(got) of \(roundLimit)")
        }
        return GameState(phase: .yourMove(placeholder: "Your next word for the model to define…"), status: "Word \(game.count + 1) of \(roundLimit) · Model got \(got)")
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let game = turns.since(gameCues) ?? []
        if youGive(game) {
            guard let last = game.last, last.outcome == nil else { return give(input, after: game, as: GameMove.ask) }
            switch GameText.judgement(input, yes: gotIt, no: missedIt) {
            case true?: return .settle(GameOutcome(text: "The model got it.", youWon: false))
            case false?: return .settle(GameOutcome(text: "You stumped the model.", youWon: true))
            case nil: return .reject("Did the model get it? Tap “\(gotIt)” or “\(missedIt)”.")
            }
        }
        guard let round = review(game).last, !round.isSettled else {
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
        if youGive(turns.since(gameCues) ?? []) {
            let definition = definition(from: reply, of: last.question)
            return definition.isEmpty ? .refuse("The model’s definition came out garbled. Press Return to ask again.") : .accept(definition)
        }
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
            if youGive(game) {
                for (index, turn) in game.enumerated() {
                    lines.heading("Word \(index + 1) · Yours")
                    lines.verse([GameLine.Piece(text: turn.question, voice: .you, isMarked: true)])
                    if let reply = turn.reply { lines.model(reply) }
                    if let outcome = turn.outcome { lines.verdict(outcome) }
                }
                continue
            }
            for (index, round) in review(game).enumerated() {
                lines.heading(round.difficulty.map { "Word \(index + 1) · \($0.rawValue.capitalized)" } ?? "Word \(index + 1)")
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
        let rounds = turns.rounds(gameCues).flatMap { game in
            youGive(game) ? game.map(yours) : review(game).map(theModels)
        }
        return rounds.isEmpty ? nil : rounds.joined(separator: "\n\n")
    }

    /// A word you gave, as Copy writes it.
    private static func yours(_ turn: ChatSession.Turn) -> String {
        var text = turn.question
        if let reply = turn.reply { text += "\nThe model: \(reply)" }
        if let outcome = turn.outcome { text += " (\(outcome.text))" }
        return text
    }

    /// A word of the model's, as Copy writes it.
    private static func theModels(_ round: Round) -> String {
        var text = round.word.meaning.isEmpty ? round.word.word : "\(round.word.word): \(round.word.meaning)"
        if let definition = round.definition, let grade = round.grade {
            text += "\nYou: \(definition) (\(grade.text))"
        } else if round.skipped != nil {
            text += "\nYou passed."
        }
        return text
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        guard let first = turns.rounds(gameCues).first else { return nil }
        return youGive(first) ? first.first?.question : review(first).first?.word.word
    }
}
