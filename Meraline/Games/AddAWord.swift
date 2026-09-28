import Foundation

/// Add-a-word: you type the first word of a sentence, or take one drawn on this Mac from `starters`, kept as the
/// model's (in another language than English, the model starts it), and you and the model add one word each in
/// turn until someone ends it with a period. Then the model
/// scores how much sense the sentence makes. The next sentence carries the same story on, so the model builds
/// on what came before: the first move of each later sentence that goes to the model brings the finished
/// sentences written out (`storySoFar`), since the turns before hold them one word a message.
nonisolated enum AddAWord: GameRules {
    static let title = "Add-a-Word"
    static let summary = "Build a sentence one word at a time"
    static let symbol = "text.badge.plus"

    /// What a drawn first word answers, as if the model had been asked for it.
    static let opening = "Start a sentence with one word."
    static let nextSentence = "Start the next sentence of the same story with one word."
    /// What goes with a first word of yours.
    static let yourOpening = "The user starts a sentence with the word below."
    static let yourNextSentence = "The user starts the next sentence of the same story with the word below."
    private static let cues: Set<String> = [opening, nextSentence, yourOpening, yourNextSentence]

    static let randomButton = "Random Word"

    /// A sentence ends here even if nobody ends it: the word that reaches it gets a period.
    static let wordLimit = 30

    static let systemPrompt = """
    You are playing Add-a-word. You and the user build a sentence together, one word at a time, taking turns. \
    When asked to start a sentence, reply with one word that could begin an interesting sentence. \
    After that, reply to each word the user adds with exactly one word that continues the sentence so far. \
    Reply with your word alone: never repeat the sentence, and no explanations, quotation marks, or Markdown. \
    When the sentence has at least six words and could end, end it by putting a period, question mark, or \
    exclamation mark right after your word. Keep sentences under twenty words. \
    Whenever the sentence is finished, by you or by the user, add a new line that scores the finished sentence \
    as “Score: N/10”, where 10 makes perfect sense in the story so far, followed by a few playful words about it. \
    If the user's word finishes the sentence, reply with the score line alone. \
    When asked to start the next sentence, carry on the same story: from the second sentence on, the story so far \
    comes with the sentence's first message, and every word you add should follow on from it.
    """

    static let invitation = "Type the first word, or take a random one. Then add one word at a time, taking turns, and end a word with a period to finish the sentence."

    /// A reply as the model wrote it: the words of its first line, and a score when it gave one.
    struct Reply: Equatable {
        var words: [String] = []
        var score: Int?
        var comment = ""
    }

    struct Sentence {
        var words: [(text: String, byYou: Bool)] = []
        var score: Int?
        var comment = ""

        var isFinished: Bool { words.last.map { AddAWord.endsSentence($0.text) } ?? false }
        var text: String { words.map(\.text).joined(separator: " ") }
    }

    static func parse(_ reply: String) -> Reply {
        var parsed = Reply()
        for line in GameText.lines(reply).map(GameText.unwrapped) {
            if parsed.score == nil, let found = GameText.score(in: line) {
                parsed.score = found.score
                parsed.comment = found.comment
            } else if parsed.words.isEmpty {
                parsed.words = GameText.words(line)
            }
        }
        return parsed
    }

    static func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"”’)")).last else { return false }
        return ".!?…".contains(last)
    }

    static func sentence(from turns: [ChatSession.Turn]) -> Sentence {
        var sentence = Sentence()
        for turn in turns {
            if !turn.question.isEmpty { sentence.words.append((turn.question, true)) }
            guard let reply = turn.reply else { continue }
            let parsed = parse(reply)
            if let word = parsed.words.first { sentence.words.append((word, false)) }
            if let score = parsed.score {
                sentence.score = score
                sentence.comment = parsed.comment
            }
        }
        return sentence
    }

    /// Left to the other side, a sentence starts with a word drawn on this Mac, one no sentence of the chat has
    /// started with while there are others. The words are English, so in another language the model starts it.
    static func opener(after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> GameOpener {
        let sentences = turns.rounds(cues)
        guard language == .english else { return .ask(sentences.isEmpty ? opening : nextSentence) }
        let used = Set(sentences.compactMap { sentence(from: $0).words.first.map { GameText.key($0.text) } })
        let word = dice.pick(from: starters) { !used.contains(GameText.key($0)) } ?? starters[0]
        return .drawn(cue: sentences.isEmpty ? opening : nextSentence, move: word)
    }

    /// How an aside gives the story so far.
    static let storySoFar = "The story so far: "

    /// The model's first sentence gets a subject, so it doesn't start the same way every game. The next ones carry
    /// the story on, and the first move of each that goes to the model, the cue or your first word or, after a word
    /// drawn on this Mac, your second, brings the finished sentences in full.
    static func aside(for turn: ChatSession.Turn, after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> String? {
        if turn.cue == opening { return "This sentence’s subject: \(OddOneOut.themes.randomElement(using: &dice) ?? OddOneOut.themes[0])." }
        let sentences = (turns + [turn]).rounds(cues)
        guard let current = sentences.last, !current.dropLast().contains(where: { $0.aside?.hasPrefix(storySoFar) == true }) else { return nil }
        let story = sentences.dropLast().map { sentence(from: $0) }.filter(\.isFinished).map(\.text)
        return story.isEmpty ? nil : storySoFar + story.joined(separator: " ")
    }

    /// Your first word starts the sentence.
    static func open(with input: String, after turns: [ChatSession.Turn]) -> GameMove {
        let words = GameText.words(GameText.firstLine(input))
        guard let word = words.first else { return .reject("One word, please.") }
        guard words.count == 1 else { return .reject("Just one word at a time. “\(word)” first?") }
        return .open(word, cue: turns.rounds(cues).isEmpty ? yourOpening : yourNextSentence)
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        let sentences = turns.rounds(cues)
        guard let current = sentences.last else {
            let opening = GameOpening(placeholder: "Type the first word, or press Return for a random one…", button: randomButton)
            return GameState(phase: .opening(opening), status: "Sentence 1")
        }
        let number = sentences.count
        let sentence = sentence(from: current)
        let count = sentence.words.count
        let status = "Sentence \(number) · \(count) \(count == 1 ? "word" : "words")"
        if current.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        if sentence.isFinished {
            let next = GameOpening(placeholder: "Type the next sentence’s first word, or press Return for a random one…", button: randomButton)
            guard let score = sentence.score else {
                return GameState(phase: .over(outcome: GameOutcome(text: "Sentence done. The story carries on in the next one.", youWon: nil), next: next), status: "Sentence \(number) done")
            }
            return GameState(
                phase: .over(outcome: GameOutcome(text: "Sentence done: \(score) out of 10 for sense. The story carries on in the next one.", youWon: nil), next: next),
                status: "Sentence \(number) · \(score)/10"
            )
        }
        return GameState(phase: .yourMove(placeholder: count >= 5 ? "Add a word, or end one with a period…" : "Add one word…"), status: status)
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let words = GameText.words(GameText.firstLine(input))
        guard let word = words.first else { return .reject("One word, please.") }
        guard words.count == 1 else { return .reject("Just one word at a time. “\(word)” first?") }
        let count = turns.rounds(cues).last.map { sentence(from: $0).words.count } ?? 0
        if count + 1 >= wordLimit, !endsSentence(word) { return .ask(word + ".") }
        return .ask(word)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        let parsed = parse(reply)
        if !last.question.isEmpty, endsSentence(last.question) {
            guard let score = parsed.score else {
                return .refuse("The model forgot to score the sentence. Press Return to ask again.")
            }
            return .accept(format(word: nil, score: score, comment: parsed.comment))
        }
        let soFar = turns.rounds(cues).last.map { sentence(from: $0).words.map(\.text) } ?? []
        guard let word = newWord(in: parsed.words, after: soFar) else {
            return .refuse(last.question.isEmpty
                ? "The model had no word to start with. Press Return to ask again."
                : "The model lost its words. Press Return to ask again.")
        }
        let finished = endsSentence(word)
        return .accept(format(word: word, score: finished ? parsed.score : nil, comment: finished ? parsed.comment : ""))
    }

    /// The model's word. A model that repeats the sentence so far before its word gets the word after it.
    static func newWord(in words: [String], after sentence: [String]) -> String? {
        guard !sentence.isEmpty, words.count > sentence.count,
              zip(words, sentence).allSatisfy({ GameText.key($0) == GameText.key($1) }) else { return words.first }
        return words[sentence.count]
    }

    /// A reply as the game keeps it, which is also how the model sees it later: the word, then the score.
    static func format(word: String?, score: Int?, comment: String) -> String {
        var lines: [String] = []
        if let word { lines.append(word) }
        if let score { lines.append(comment.isEmpty ? "Score: \(score)/10" : "Score: \(score)/10 — \(comment)") }
        return lines.joined(separator: "\n")
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for round in turns.rounds(cues) {
            let sentence = sentence(from: round)
            lines.verse(sentence.words.enumerated().map { index, word in
                GameLine.Piece(text: (index == 0 ? "" : " ") + word.text, voice: word.byYou ? .you : .model)
            })
            if sentence.isFinished, let score = sentence.score {
                lines.verdict(GameOutcome(text: sentence.comment.isEmpty ? "\(score)/10" : "\(score)/10 · \(sentence.comment)", youWon: nil))
            }
        }
        return lines.all
    }

    /// The story so far, a sentence a line, each with its score.
    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let sentences = turns.rounds(cues).map { sentence(from: $0) }.filter { !$0.words.isEmpty }
        guard !sentences.isEmpty else { return nil }
        return sentences.map { sentence in
            sentence.score.map { "\(sentence.text) (\($0)/10)" } ?? sentence.text
        }.joined(separator: "\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        turns.rounds(cues).first.map { sentence(from: $0).text }
    }

    /// Words a sentence can start with, anywhere in a story.
    static let starters = [
        "Yesterday", "Suddenly", "Once", "My", "The", "Every", "Nobody", "Somewhere", "Tomorrow", "Grandma",
        "Meanwhile", "After", "Before", "Although", "When", "If", "Today", "Last", "Under", "Behind", "Three", "Our",
        "Their", "Most", "Never", "Always", "Honestly", "Luckily", "Sadly", "Later", "Despite", "Somehow", "Tonight",
        "During", "Whenever", "Everyone", "Only", "Some", "This", "Two", "Seven", "Captain", "Doctor", "Penguins",
        "Cats", "Pirates", "Robots", "Wizards", "Dragons", "Scientists", "Monday", "Winter", "Breakfast", "Nothing",
        "Why", "How", "Maybe", "Clearly", "Apparently", "Unfortunately", "Beneath", "Inside", "Outside", "Above",
        "Grandpa", "Aliens", "Ghosts", "Everybody", "Nine", "Midnight", "Sunday", "Spaghetti"
    ]
}

nonisolated extension AddAWord {
    /// A sentence's numbers for Settings › Usage: whether you started it, its words, and its score for sense.
    static func figures(ofRoundEndingIn turns: [ChatSession.Turn]) -> GameFigures {
        var figures = GameFigures()
        guard let round = turns.rounds(cues).last else { return figures }
        if round.first?.cue == yourOpening || round.first?.cue == yourNextSentence { figures.add(1, to: .opened) }
        let sentence = sentence(from: round)
        figures.record(sentence.words.count, as: .words)
        if let score = sentence.score {
            figures.add(1, to: .rated)
            figures.record(score, as: .score)
        }
        return figures
    }
}
