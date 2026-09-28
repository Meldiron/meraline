import Foundation

/// Longest word: this Mac draws nine letters, and you and the model each make the longest word you can from them,
/// each letter used no more often than it was drawn. The model picks first, and its word stays hidden until yours is
/// in, so neither side sees the other's and a round takes one trip to the model. This Mac judges both words: the
/// letters by `spending(_:from:)`, and whether it is a word by macOS's spell checker (`WordCheck`), in the round's
/// language. The longer word wins the round, and when this Mac's word list knows a longer one, it shows after it.
///
/// A round is two turns: the model's, with the cue, the letters in its aside, and its word as the reply; then yours,
/// your word with the round's outcome, which nothing is sent for. The aside also names the language the round is
/// played in, so your word is checked in the language the model was asked for.
nonisolated enum LongestWord: GameRules {
    static let title = "Longest Word"
    static let summary = "Make the longest word from nine letters, against the model"
    static let symbol = "a.square"

    /// How many letters a round draws.
    static let letterCount = 9

    static let opening = "Make your word from this round's letters."
    static let nextRound = "A new round: make your word from these letters."
    private static let cues: Set<String> = [opening, nextRound]

    static let systemPrompt = """
    You are playing Longest word. Each round the message gives nine letters, and you and the user each make \
    the longest English word you can from them, using each letter no more often than it appears. \
    You pick first, and the user sees your word only once they have played theirs. \
    Reply with your word alone, in capital letters: one real, everyday word, not a name, an abbreviation, \
    or a hyphenated word. A word that needs a letter that isn't there, or more of one than there is, scores \
    nothing, so check yours letter by letter before you answer. A letter with an accent counts as the same \
    letter without it. No explanations, quotation marks, or Markdown.
    """

    static let invitation = "This Mac draws nine letters, and you and the model each make the longest word you can from them. The model picks first, and its word stays hidden until you play yours."
    static let newLetters = "New Letters"
    /// What the model's reply keeps when it has no word.
    static let noWord = "PASS"

    /// How an aside gives the round's letters, and the language its words are in.
    static let lettersIntro = "The letters: "
    static let languageIntro = "The word must be "

    /// The bag the letters come from, weighted as the TV show Countdown's: E and A often, J, Q, X, and Z seldom.
    static let vowels: [(letter: Character, weight: Int)] = [("a", 15), ("e", 21), ("i", 13), ("o", 13), ("u", 5)]
    static let consonants: [(letter: Character, weight: Int)] = [
        ("b", 2), ("c", 3), ("d", 6), ("f", 2), ("g", 3), ("h", 2), ("j", 1), ("k", 1), ("l", 5), ("m", 4), ("n", 8),
        ("p", 4), ("q", 1), ("r", 9), ("s", 9), ("t", 9), ("v", 1), ("w", 1), ("x", 1), ("y", 1), ("z", 1)
    ]

    /// Nine letters, three or four of them vowels, no vowel more than three times and no consonant more than twice,
    /// and a Q only with a U. In English they are drawn again until this Mac knows a word of six letters in them.
    static func draw(dice: inout GameDice, in language: AnswerLanguage) -> [Character] {
        var letters: [Character] = []
        for _ in 0..<20 {
            let vowelCount = [3, 4, 4].randomElement(using: &dice) ?? 4
            letters = pick(vowelCount, from: vowels, atMost: 3, dice: &dice)
                + pick(letterCount - vowelCount, from: consonants, atMost: 2, dice: &dice)
            letters.shuffle(using: &dice)
            if letters.contains("q"), !letters.contains("u") { continue }
            guard language == .english else { return letters }
            if (WordCheck.longestWords(from: letters).first?.count ?? 0) >= 6 { return letters }
        }
        return letters
    }

    private static func pick(_ count: Int, from bag: [(letter: Character, weight: Int)], atMost limit: Int, dice: inout GameDice) -> [Character] {
        let tiles = bag.flatMap { Array(repeating: $0.letter, count: $0.weight) }
        var picked: [Character] = []
        while picked.count < count, let tile = tiles.randomElement(using: &dice) {
            if picked.filter({ $0 == tile }).count < limit { picked.append(tile) }
        }
        return picked
    }

    /// Each round's letters are drawn here and go to the model with the cue, with the language its word is in.
    static func aside(for turn: ChatSession.Turn, after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> String? {
        guard turn.cue.map(cues.contains) == true else { return nil }
        let letters = draw(dice: &dice, in: language)
        return "\(lettersIntro)\(spaced(letters)). \(languageIntro)\(language.name)."
    }

    /// “R A T E S”.
    static func spaced(_ letters: [Character]) -> String {
        letters.map { $0.uppercased() }.joined(separator: " ")
    }

    /// A round's letters, from its aside.
    static func letters(of round: [ChatSession.Turn]) -> [Character]? {
        guard let aside = round.first?.aside, let start = aside.range(of: lettersIntro) else { return nil }
        let letters = aside[start.upperBound...].prefix { $0 != "." }.split(separator: " ").compactMap { $0.count == 1 ? $0.lowercased().first : nil }
        return letters.isEmpty ? nil : letters
    }

    /// The language a round's words are in, from its aside; English when it names none.
    static func language(of round: [ChatSession.Turn]) -> AnswerLanguage {
        guard let aside = round.first?.aside, let start = aside.range(of: languageIntro) else { return .english }
        let name = String(aside[start.upperBound...].prefix { $0 != "." })
        return AnswerLanguage.allCases.first { $0.name == name } ?? .english
    }

    /// A word as the letters pay for it: lower case, accents off, letters only.
    static func spelled(_ word: String) -> String {
        String(GameText.folded(word.lowercased()).filter { $0.isLetter && $0.isASCII })
    }

    /// The letters left once `word` is paid for, or nil when it can't be: a letter missing, or not enough of one.
    static func spending(_ word: String, from letters: [Character]) -> [Character]? {
        var left = letters
        for letter in word {
            guard let index = left.firstIndex(of: letter) else { return nil }
            left.remove(at: index)
        }
        return left
    }

    /// The letters `word` needs that aren't there to spare, each once, in capitals.
    static func shortfall(of word: String, in letters: [Character]) -> [String] {
        var left = letters
        var short: [String] = []
        for letter in word {
            if let index = left.firstIndex(of: letter) {
                left.remove(at: index)
            } else if !short.contains(letter.uppercased()) {
                short.append(letter.uppercased())
            }
        }
        return short
    }

    /// The model's word in its reply: the first word in capitals, as the rules ask, else the longest the letters
    /// pay for, else the first.
    static func word(inReply reply: String, letters: [Character]?) -> String? {
        let words = GameText.words(GameText.firstLine(reply)).map(GameText.withoutEndPunctuation).filter { !spelled($0).isEmpty }
        if let capitals = words.first(where: { word in
            let letters = word.filter(\.isLetter)
            return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
        }) { return capitals }
        if let letters, let longest = words.filter({ spending(spelled($0), from: letters) != nil }).max(by: { spelled($0).count < spelled($1).count }) {
            return longest
        }
        return words.first
    }

    /// What a word is worth: its letters when it counts, or why it doesn't.
    enum Verdict: Equatable {
        case counts(Int)
        case missingLetters
        case notAWord
        case none
    }

    static func verdict(of word: String?, letters: [Character], in language: AnswerLanguage) -> Verdict {
        guard let word, !GameText.isGivingUp(word) else { return .none }
        let spent = spelled(word)
        guard spent.count >= 2, spending(spent, from: letters) != nil else { return .missingLetters }
        guard WordCheck.isWord(word, in: language) != false else { return .notAWord }
        return .counts(spent.count)
    }

    /// Your word counts once it is in: the letters paid for it, and the dictionary knew it or you insisted.
    static func yourVerdict(_ word: String) -> Verdict {
        GameText.isGivingUp(word) ? .none : .counts(spelled(word).count)
    }

    /// The model's word this round, once it has picked one.
    static func modelWord(in round: [ChatSession.Turn]) -> String? {
        guard let reply = round.first?.reply, reply != noWord else { return nil }
        return reply
    }

    /// How a round went: your word, checked already, against the model's, which is checked here.
    static func outcome(yours: String?, model: String?, letters: [Character], in language: AnswerLanguage) -> GameOutcome {
        let your = yours?.uppercased() ?? ""
        let its = model?.uppercased() ?? ""
        let theirs = verdict(of: model, letters: letters, in: language)
        guard let yours else {
            if case .counts(let length) = theirs {
                return GameOutcome(text: "You passed, and the model’s \(its) takes it, \(length) letters.", youWon: false)
            }
            return GameOutcome(text: "You passed, and the model found no word either.", youWon: nil)
        }
        let mine = spelled(yours).count
        switch theirs {
        case .counts(let length) where mine > length:
            return GameOutcome(text: "Your \(your) beats the model’s \(its), \(mine) letters to \(length).", youWon: true)
        case .counts(let length) where mine < length:
            return GameOutcome(text: "The model’s \(its) beats your \(your), \(length) letters to \(mine).", youWon: false)
        case .counts:
            if spelled(yours) == spelled(model ?? "") { return GameOutcome(text: "A tie: you both found \(your).", youWon: nil) }
            return GameOutcome(text: "A tie: \(your) and \(its), \(mine) letters each.", youWon: nil)
        case .missingLetters:
            return GameOutcome(text: "The model’s \(its) needs letters that aren’t there, so your \(your) wins.", youWon: true)
        case .notAWord:
            return GameOutcome(text: "The model’s \(its) isn’t in this Mac’s dictionary, so your \(your) wins.", youWon: true)
        case .none:
            return GameOutcome(text: "The model found no word, so your \(your) wins.", youWon: true)
        }
    }

    /// The model picks first, every round, the first with `opening`.
    static func opener(after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> GameOpener {
        .ask(turns.isEmpty ? opening : nextRound)
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        let rounds = turns.rounds(cues)
        guard let round = rounds.last else { return GameState(phase: .modelMoves(cue: opening), status: title) }
        let status = "Round \(rounds.count)"
        guard round.first?.isComplete == true else { return GameState(phase: .waiting, status: status) }
        if let outcome = round.dropFirst().first?.outcome {
            let next = GameOpening(placeholder: "Press Return for new letters…", button: newLetters, takesYourMove: false)
            return GameState(phase: .over(outcome: outcome, next: next), status: "Round \(rounds.count) done")
        }
        let hints = letters(of: round).map { Self.hints(for: $0, in: language(of: round)) } ?? []
        return GameState(phase: .yourMove(placeholder: "Your longest word from these letters…", hints: hints), status: status)
    }

    /// What this Mac's word list knows about the longest words the letters make, in English.
    static func hints(for letters: [Character], in language: AnswerLanguage) -> [String] {
        guard language == .english else { return [] }
        let words = WordCheck.longestWords(from: letters)
        guard let top = words.first else { return [] }
        var hints = [
            "This Mac knows a word of \(top.count) letters in these.",
            "A word of \(top.count) letters starts with “\(top.prefix(2).uppercased())”."
        ]
        if let other = words.dropFirst().first(where: { $0.first != top.first }) {
            hints.append("Try a word of \(other.count) letters starting with “\(other.prefix(1).uppercased())”.")
        }
        return hints
    }

    /// Your word, once the letters pay for it and the dictionary knows it, settles the round on this Mac.
    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        guard let round = turns.since(cues), let letters = letters(of: round) else { return .reject("Wait for the letters.") }
        let words = GameText.words(GameText.firstLine(input)).map(GameText.withoutEndPunctuation)
        guard let first = words.first else { return .reject("Make a word from the letters first.") }
        let language = language(of: round)
        let model = modelWord(in: round)
        if words.count == 1, GameText.isGivingUp(first) {
            return .record(first, outcome: outcome(yours: nil, model: model, letters: letters, in: language))
        }
        guard words.count == 1 else { return .reject("One word, please.") }
        let word = spelled(first)
        guard word.count >= 2 else { return .reject("A word of two letters or more.") }
        let short = shortfall(of: word, in: letters)
        guard short.isEmpty else {
            return .reject("The letters can’t make “\(first.uppercased())”: there’s no \(GameText.list(short)) to spare.")
        }
        // The dictionary misses a few real words, such as “relisted”, so yours counts when you send it again.
        guard insisting || WordCheck.isWord(first, in: language) != false else {
            return .reject("“\(first.uppercased())” isn’t in this Mac’s dictionary. Try another, or send it again to count it anyway.")
        }
        return .record(first.uppercased(), outcome: outcome(yours: first, model: model, letters: letters, in: language))
    }

    /// The model's word, in capitals, as the round keeps it until yours is in; `noWord` when it has none.
    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        let round = turns.since(cues) ?? []
        guard let word = word(inReply: reply, letters: letters(of: round)), !GameText.isGivingUp(word) else { return .accept(noWord) }
        return .accept(word.uppercased())
    }

    /// A word and its length, or why it doesn't count.
    private static func label(_ word: String?, _ verdict: Verdict) -> String {
        let word = word?.uppercased() ?? ""
        switch verdict {
        case .counts(let length): return "\(word), \(length) letters"
        case .missingLetters: return "\(word), not in the letters"
        case .notAWord: return "\(word), not a word"
        case .none: return "no word"
        }
    }

    /// Whether this Mac knows a word longer than both, to show once the round is over.
    static func longer(than round: [ChatSession.Turn], letters: [Character]) -> String? {
        let language = language(of: round)
        guard language == .english, let best = WordCheck.longestWords(from: letters).first else { return nil }
        let yours = round.dropFirst().first.map { yourVerdict($0.question) }
        let theirs = verdict(of: modelWord(in: round), letters: letters, in: language)
        let lengths = [yours, theirs].compactMap { verdict -> Int? in
            if case .counts(let length)? = verdict { length } else { nil }
        }
        return best.count > (lengths.max() ?? 0) ? best : nil
    }

    /// Each round's letters, the model's pick while it is hidden, then both words, who won, and a longer word when
    /// this Mac knows one.
    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (number, round) in turns.rounds(cues).enumerated() {
            guard let letters = letters(of: round) else { continue }
            lines.heading("Round \(number + 1)")
            lines.verse([.init(text: spaced(letters), voice: .model)])
            guard let yours = round.dropFirst().first, let outcome = yours.outcome else {
                if round.first?.reply != nil { lines.note("The model has picked its word.") }
                continue
            }
            let language = language(of: round)
            let model = modelWord(in: round)
            lines.you("You: \(label(yours.question, yourVerdict(yours.question)))")
            lines.model("Model: \(label(model, verdict(of: model, letters: letters, in: language)))")
            lines.verdict(outcome)
            if let longer = longer(than: round, letters: letters) {
                lines.note("This Mac knows a longer one: \(longer.uppercased()), \(longer.count) letters.")
            }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let rounds = turns.rounds(cues).compactMap { round -> String? in
            guard let letters = letters(of: round) else { return nil }
            var text = ["Letters: \(spaced(letters))"]
            if let yours = round.dropFirst().first, let outcome = yours.outcome {
                let language = language(of: round)
                let model = modelWord(in: round)
                text.append("You: \(label(yours.question, yourVerdict(yours.question)))")
                text.append("Model: \(label(model, verdict(of: model, letters: letters, in: language)))")
                text.append(outcome.text)
                if let longer = longer(than: round, letters: letters) {
                    text.append("This Mac knows a longer one: \(longer.uppercased()).")
                }
            }
            return text.joined(separator: "\n")
        }
        return rounds.isEmpty ? nil : rounds.joined(separator: "\n\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        let words = turns.rounds(cues).compactMap { $0.dropFirst().first?.question }.filter { !GameText.isGivingUp($0) }
        return words.isEmpty ? nil : words.prefix(3).map { $0.uppercased() }.joined(separator: " · ")
    }
}
