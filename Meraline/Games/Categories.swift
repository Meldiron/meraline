import Foundation

/// Categories: the model picks a category, and you and the model take turns naming things in it, you
/// first. The model judges each of yours; one that doesn't fit comes back to you. Six each, unless the
/// model runs out, repeats itself, or you give up.
nonisolated enum Categories: GameRules {
    static let title = "Categories"
    static let summary = "Take turns naming things in a category"
    static let symbol = "square.grid.2x2"

    static let perSide = 6
    static let limit = perSide * 2

    static let opening = "Pick a category."
    static let nextCategory = "Pick a new category, different from the ones so far."
    private static let cues: Set<String> = [opening, nextCategory]

    static let systemPrompt = """
    You are playing Categories. When asked to pick a category, reply with just the name of a fun, broad category \
    that has plenty of members, like Kitchen, Animals, or Things at the beach, and nothing else. \
    Then the user and you take turns naming things that belong to it, the user first. \
    Reply to each thing the user names with one line. If it belongs to the category and nobody has named it yet \
    this round, write “OK: ” followed by one new thing of your own that belongs and hasn't been named. \
    If it doesn't belong, or was already named, write “NO: ” followed by a short, friendly reason. \
    If you can't think of anything new, write “OK: PASS”. No explanations, quotation marks, or Markdown.
    """

    static let invitation = "The model picks a category. Take turns naming things in it, you first; type pass to give up."

    struct Round {
        var category = ""
        var named: [(text: String, byYou: Bool)] = []
        var ending: GameOutcome?
    }

    static func review(_ turns: [ChatSession.Turn]) -> Round {
        var round = Round()
        guard let first = turns.first else { return round }
        round.category = first.reply ?? ""
        for turn in turns.dropFirst() {
            if let outcome = turn.outcome {
                round.ending = outcome
                break
            }
            if !turn.question.isEmpty { round.named.append((turn.question, true)) }
            guard let reply = turn.reply else { continue }
            let word = GameText.verdict(of: reply).rest
            if GameText.isGivingUp(word) {
                round.ending = GameOutcome(text: "The model ran out of ideas. You win!", youWon: true)
                break
            }
            let repeated = round.named.contains { GameText.sameWord($0.text, word) }
            round.named.append((word, false))
            if repeated {
                round.ending = GameOutcome(text: "Foul: “\(word)” was named already. You win!", youWon: true)
                break
            }
        }
        if round.ending == nil, round.named.count >= limit {
            round.ending = GameOutcome(text: "Full house: \(perSide) each and nobody slipped. A draw.", youWon: nil)
        }
        return round
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let current = turns.since(cues) else { return GameState(phase: .modelMoves(cue: opening), status: title) }
        let round = review(current)
        let status = round.category.isEmpty ? title : "\(round.category) · \(round.named.count) of \(limit)"
        if current.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        if let ending = round.ending {
            return GameState(
                phase: .over(outcome: ending, rematch: Rematch(cue: nextCategory, placeholder: "Press Return for a new category…")),
                status: status
            )
        }
        return GameState(phase: .yourMove(placeholder: "Name one for “\(round.category)”…"), status: status)
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let item = GameText.withoutEndPunctuation(GameText.unwrapped(GameText.firstLine(input)))
        guard !item.isEmpty else { return .reject("Name something first.") }
        if GameText.isGivingUp(item) {
            return .record(item, outcome: GameOutcome(text: "You passed, so the model takes this round.", youWon: false))
        }
        guard GameText.words(item).count <= 4 else { return .reject("Name one thing, in a word or a few.") }
        if let taken = review(turns.since(cues) ?? []).named.first(where: { GameText.sameWord($0.text, item) }) {
            return .reject("“\(taken.text)” is taken already. Name something else.")
        }
        return .ask(item)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        if last.cue != nil {
            let name = categoryName(reply)
            return name.isEmpty ? .refuse("The model couldn’t think of a category. Press Return to ask again.") : .accept(name)
        }
        let (accepted, rest) = GameText.verdict(of: reply)
        if accepted == false {
            return .refuse(rest.isEmpty ? "The model says “\(last.question)” doesn’t count. Try another." : "Not quite: \(GameText.sentence(rest))")
        }
        var word = rest
        if GameText.words(word).count > 4, let colon = word.lastIndex(of: ":") {
            word = String(word[word.index(after: colon)...])
        }
        word = GameText.withoutEndPunctuation(GameText.unwrapped(word))
        return .accept("OK: \(word.isEmpty || GameText.isGivingUp(word) ? "PASS" : word)")
    }

    static func categoryName(_ reply: String) -> String {
        var name = GameText.unwrapped(GameText.firstLine(reply))
        for prefix in ["category:", "the category is"] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return GameText.withoutEndPunctuation(GameText.unwrapped(name))
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for current in turns.rounds(cues) {
            let round = review(current)
            guard !round.category.isEmpty else { continue }
            lines.heading(round.category)
            lines.verse(GameLines.chain(round.named.map { ($0.text, $0.byYou ? .you : .model) }, separator: " · "))
            if let ending = round.ending { lines.verdict(ending) }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let rounds = turns.rounds(cues).map(review).filter { !$0.category.isEmpty }
        guard !rounds.isEmpty else { return nil }
        return rounds.map { round in
            var text = "\(round.category): \(round.named.map(\.text).joined(separator: ", "))"
            if let ending = round.ending { text += "\n\(ending.text)" }
            return text
        }.joined(separator: "\n\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        turns.first?.reply
    }
}
