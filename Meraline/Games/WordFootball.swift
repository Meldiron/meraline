import Foundation

/// Word football: the model kicks off with a word, and you and the model take turns playing words that
/// start with the last letter of the one before. The model referees yours; a word it doesn't know comes
/// back to you. Eight each is full time, unless the model fouls, runs out, or you give up.
nonisolated enum WordFootball: GameRules {
    static let title = "Word Football"
    static let summary = "Chain words, last letter to first"
    static let symbol = "soccerball"

    static let perSide = 8
    static let limit = perSide * 2

    static let opening = "Kick off with one word."
    static let rematchCue = "Kick off a new match with a different word."
    private static let cues: Set<String> = [opening, rematchCue]

    static let systemPrompt = """
    You are playing Word football, a word-chain game. When asked to kick off, reply with one common English word \
    and nothing else. Then the user and you take turns. Each word must be a real English word that starts with \
    the last letter of the word before it, and no word may be played twice in a match. \
    Reply to each word the user plays with one line. If it is a real English word, write “OK: ” followed by your \
    own word, which must start with the last letter of the user's word and must not have been played yet. \
    If it isn't a real English word, write “NO: ” followed by a short, friendly reason. \
    If you can't think of a word, write “OK: PASS”. No explanations, quotation marks, or Markdown.
    """

    static let invitation = "The model kicks off. Each word starts with the last letter of the one before; type pass to give up."

    struct Match {
        var words: [(text: String, byYou: Bool)] = []
        var ending: GameOutcome?

        /// Words played after the kickoff.
        var played: Int { max(words.count - 1, 0) }
        var nextLetter: Character? { words.last.flatMap { WordFootball.lastLetter(of: $0.text) } }
    }

    static func firstLetter(of word: String) -> Character? { word.lowercased().first(where: \.isLetter) }
    static func lastLetter(of word: String) -> Character? { word.lowercased().last(where: \.isLetter) }

    /// One word, lower case, letters only.
    static func cleanWord(_ text: String) -> String {
        String((GameText.words(text).first ?? "").lowercased().filter(\.isLetter))
    }

    static func review(_ turns: [ChatSession.Turn]) -> Match {
        var match = Match()
        guard let kickoff = turns.first else { return match }
        if let word = kickoff.reply { match.words.append((word, false)) }
        for turn in turns.dropFirst() {
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

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let current = turns.since(cues) else { return GameState(phase: .modelMoves(cue: opening), status: title) }
        let match = review(current)
        let status = "\(match.played) of \(limit) words"
        if current.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        if let ending = match.ending {
            return GameState(
                phase: .over(summary: ending.text + " Press Return for a new match.", rematch: Rematch(cue: rematchCue, placeholder: "Press Return for a new match…")),
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
        if let needed = match.nextLetter, word.first != needed {
            return .reject("“\(word)” starts with “\(word.first.map { $0.uppercased() } ?? "")”. You need a word starting with “\(needed.uppercased())”.")
        }
        if match.words.contains(where: { GameText.key($0.text) == word }) {
            return .reject("“\(word)” was played already. Try another.")
        }
        return .ask(word)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        if last.cue != nil {
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
        turns.first?.reply
    }
}
