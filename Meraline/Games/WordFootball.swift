import Foundation

/// Word football: you kick off with a word, or a word drawn on this Mac from `kickoffs` kicks off for the model
/// (in another language than English, the model kicks off itself), and you and the model take turns playing
/// words that start with the last letter of the one before, a letter with an accent counting as its plain
/// letter. The model referees yours; a word it doesn't know comes back to you. Eight each is full time, unless
/// the model fouls, runs out, or you give up.
///
/// A kind of word for each of the model's is drawn on this Mac too: left to itself, the model kicks off with
/// the same word every match and answers each letter the same way.
nonisolated enum WordFootball: GameRules {
    static let title = "Word Football"
    static let summary = "Chain words, last letter to first"
    static let symbol = "soccerball"

    static let perSide = 8
    static let limit = perSide * 2

    /// What the model is asked to kick off with, and what a drawn kickoff answers as if it had been.
    static let opening = "Kick off with one word."
    static let rematchCue = "Kick off a new match with a different word."
    private static let modelKickoffs: Set<String> = [opening, rematchCue]
    /// What goes with a kickoff of yours.
    static let yourKickoff = "The user kicks off with the word below."
    private static let cues: Set<String> = [opening, rematchCue, yourKickoff]

    static let randomButton = "Random Word"

    static let systemPrompt = """
    You are playing Word football, a word-chain game. The user and you take turns playing words: each must be a \
    real English word that starts with the last letter of the word before it, and no word may be played twice in \
    a match. A match kicks off with a word the user plays, or with one drawn for you; when asked to kick off, \
    reply with one common word and nothing else. \
    Reply to each word the user plays with one line. If it is a real English word, write “OK: ” followed by your \
    own word, which must start with the last letter of the user's word and must not have been played yet; \
    when the message suggests a kind of word, play one of that kind if one fits. \
    If it isn't a real English word, write “NO: ” followed by a short, friendly reason. \
    If you can't think of a word, write “OK: PASS”. No explanations, quotation marks, or Markdown.
    """

    static let invitation = "Kick off with a word, or take a random one. Each word starts with the last letter of the one before; type pass to give up."

    struct Match {
        var words: [(text: String, byYou: Bool)] = []
        var ending: GameOutcome?

        /// Words played after the kickoff.
        var played: Int { max(words.count - 1, 0) }
        var nextLetter: Character? { words.last.flatMap { WordFootball.lastLetter(of: $0.text) } }
    }

    static func firstLetter(of word: String) -> Character? { GameText.folded(word.lowercased()).first(where: \.isLetter) }
    static func lastLetter(of word: String) -> Character? { GameText.folded(word.lowercased()).last(where: \.isLetter) }

    /// One word, lower case, letters only.
    static func cleanWord(_ text: String) -> String {
        String((GameText.words(text).first ?? "").lowercased().filter(\.isLetter))
    }

    static func review(_ turns: [ChatSession.Turn]) -> Match {
        var match = Match()
        guard let kickoff = turns.first else { return match }
        // A kickoff of the model's side is its reply; yours is a word the model answers like any other.
        let isYours = kickoff.cue == yourKickoff
        if !isYours, let word = kickoff.reply { match.words.append((word, false)) }
        for turn in isYours ? turns[...] : turns.dropFirst() {
            if let outcome = turn.outcome {
                match.ending = outcome
                break
            }
            if !turn.question.isEmpty { match.words.append((turn.question, true)) }
            guard let reply = turn.reply else { continue }
            let word = GameText.verdict(of: reply).rest
            if GameText.isGivingUp(word) {
                match.ending = GameOutcome(text: "Goal! The model couldn’t find a word. You win!", youWon: true)
                break
            }
            let needed = match.nextLetter
            let repeated = match.words.contains { GameText.key($0.text) == GameText.key(word) }
            match.words.append((word, false))
            if let needed, firstLetter(of: word) != needed {
                match.ending = GameOutcome(text: "Foul! “\(word)” doesn’t start with “\(needed.uppercased())”. You win!", youWon: true)
                break
            }
            if repeated {
                match.ending = GameOutcome(text: "Foul! “\(word)” was played already. You win!", youWon: true)
                break
            }
        }
        if match.ending == nil, match.played >= limit {
            match.ending = GameOutcome(text: "Full time: \(limit) words and no fouls. A draw.", youWon: nil)
        }
        return match
    }

    /// Your word gets a kind of word for the model's answer, and the model's own kickoff a kind to kick off with.
    static func aside(for turn: ChatSession.Turn, after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> String? {
        let kind = kinds.randomElement(using: &dice) ?? kinds[0]
        if turn.cue.map(modelKickoffs.contains) == true { return "Kick off with a common word, \(kind) if one comes to mind." }
        guard !turn.question.isEmpty else { return nil }
        return "For your own word, try \(kind) if one fits."
    }

    /// Left to the other side, a match kicks off with a word drawn on this Mac, one the chat hasn't played while
    /// there are others, kept as the model's. The words are English, so in another language the model kicks off.
    static func opener(after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> GameOpener {
        let cue = turns.isEmpty ? opening : rematchCue
        guard language == .english else { return .ask(cue) }
        let played = Set(turns.rounds(cues).flatMap { review($0).words.map { GameText.key($0.text) } })
        let word = dice.pick(from: kickoffs) { !played.contains($0) } ?? kickoffs[0]
        return .drawn(cue: cue, move: word)
    }

    /// Your word kicks off the match.
    static func open(with input: String, after turns: [ChatSession.Turn]) -> GameMove {
        let words = GameText.words(GameText.firstLine(input))
        guard let first = words.first, !GameText.isGivingUp(first) else { return .reject("Kick off with a word first.") }
        guard words.count == 1 else { return .reject("One word at a time.") }
        let word = String(first.lowercased().filter(\.isLetter))
        guard word.count >= 2 else { return .reject("A word of at least two letters, please.") }
        return .open(word, cue: yourKickoff)
    }

    /// Common words that kick off a match, a few for most letters.
    static let kickoffs = [
        "apple", "anchor", "arrow", "banana", "basket", "button", "candle", "castle", "cactus", "dragon", "drum",
        "desert", "eagle", "engine", "elbow", "forest", "feather", "fountain", "garden", "guitar", "glacier",
        "hammer", "harbor", "helmet", "island", "igloo", "insect", "jacket", "jungle", "journey", "kitten",
        "kettle", "keyboard", "lantern", "lemon", "ladder", "mountain", "mirror", "marble", "needle", "noodle",
        "orange", "octopus", "oven", "pencil", "parrot", "pillow", "planet", "quilt", "queen", "rocket", "river",
        "rabbit", "saddle", "spoon", "sunflower", "tiger", "teapot", "tunnel", "umbrella", "unicorn", "violin",
        "valley", "velvet", "window", "walrus", "wizard", "yogurt", "yacht", "zebra", "zipper", "bridge", "cloud",
        "daisy", "ember", "falcon", "goblin", "honey", "ivory", "jigsaw", "koala", "lizard", "magnet", "nest",
        "olive", "puzzle", "radio", "shadow", "thunder", "volcano", "wagon", "blanket", "comet", "dolphin",
        "garlic", "harp", "meadow", "pirate", "robot", "scarf", "tractor", "whistle"
    ]

    /// The kinds of word the model is nudged toward, so its words differ from match to match.
    static let kinds = [
        "an animal", "a food", "something in a kitchen", "a place", "a job", "something you wear", "a sport",
        "a plant", "something in the sky", "a tool", "a musical instrument", "a vehicle", "something at the beach",
        "a toy", "a drink", "a feeling", "something in an office", "a kind of weather", "a building", "a city",
        "a country", "a piece of furniture", "something sweet", "a bird", "a sea creature", "something in a bathroom",
        "a verb", "an adjective", "a part of the body", "something made of metal", "something in a garden",
        "a color", "something at school", "a fruit", "a vegetable", "an insect", "a hobby", "something in space",
        "a shape", "something that makes a noise"
    ]

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let current = turns.since(cues) else {
            let opening = GameOpening(placeholder: "Kick off with a word, or press Return for a random one…", button: randomButton)
            return GameState(phase: .opening(opening), status: title)
        }
        let match = review(current)
        let status = "\(match.played) of \(limit) words"
        if current.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        if let ending = match.ending {
            return GameState(
                phase: .over(outcome: ending, next: GameOpening(placeholder: "Kick off a new match with a word, or press Return for a random one…", button: randomButton)),
                status: status
            )
        }
        let letter = match.nextLetter.map { $0.uppercased() } ?? ""
        return GameState(phase: .yourMove(placeholder: letter.isEmpty ? "Your word…" : "A word starting with “\(letter)”…"), status: status)
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let words = GameText.words(GameText.firstLine(input))
        guard let first = words.first else { return .reject("Play a word first.") }
        if words.count == 1, GameText.isGivingUp(first) {
            return .record(first, outcome: GameOutcome(text: "You passed, so the model takes this match.", youWon: false))
        }
        guard words.count == 1 else { return .reject("One word at a time.") }
        let word = String(first.lowercased().filter(\.isLetter))
        guard word.count >= 2 else { return .reject("A word of at least two letters, please.") }
        let match = review(turns.since(cues) ?? [])
        if let needed = match.nextLetter, firstLetter(of: word) != needed {
            return .reject("“\(word)” starts with “\(word.first.map { $0.uppercased() } ?? "")”. You need a word starting with “\(needed.uppercased())”.")
        }
        if match.words.contains(where: { GameText.key($0.text) == word }) {
            return .reject("“\(word)” was played already. Try another.")
        }
        return .ask(word)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        if last.cue.map(modelKickoffs.contains) == true {
            let word = cleanWord(GameText.firstLine(reply))
            return word.count < 2 ? .refuse("The model fluffed the kickoff. Press Return to try again.") : .accept(word)
        }
        let (accepted, rest) = GameText.verdict(of: reply)
        if accepted == false {
            return .refuse(rest.isEmpty ? "The ref says “\(last.question)” isn’t a word. Try another." : "The ref says no: \(GameText.sentence(rest))")
        }
        let word = cleanWord(rest)
        return .accept("OK: \(word.isEmpty || GameText.isGivingUp(word) ? "PASS" : word)")
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (index, current) in turns.rounds(cues).enumerated() {
            if index > 0 { lines.note("New match") }
            let match = review(current)
            lines.verse(GameLines.chain(match.words.map { ($0.text, $0.byYou ? .you : .model) }, separator: " → "))
            if let ending = match.ending { lines.verdict(ending) }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let matches = turns.rounds(cues).map(review).filter { !$0.words.isEmpty }
        guard !matches.isEmpty else { return nil }
        return matches.map { match in
            var text = match.words.map(\.text).joined(separator: " → ")
            if let ending = match.ending { text += "\n\(ending.text)" }
            return text
        }.joined(separator: "\n\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        turns.rounds(cues).first.flatMap { review($0).words.first?.text }
    }
}
