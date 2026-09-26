import Foundation

/// Letter auction: the model is the banker. It deals a shared pool of letters, each with a price, and you
/// and the banker take turns spending them on words, you first. A word banks what its letters are worth,
/// and the letters it spends are gone for both of you. The banker also judges your words; one it doesn't
/// know comes back to you. The richer side wins when the pool runs dry, after six words each, or when you
/// close the bank with pass.
///
/// This Mac keeps the books: it checks your word against the pool before asking, and the banker's word
/// after, and a word of the banker's that the pool can't pay for earns nothing. Words the deal makes travel
/// hidden after a bar ("R A T E … | slink, pure") and serve as hints.
nonisolated enum LetterAuction: GameRules {
    static let title = "Letter Auction"
    static let summary = "Spend a shared pool of letters on words, against the banker"
    static let symbol = "banknote"

    static let wordsPerSide = 6
    static let limit = wordsPerSide * 2
    /// How many letters a deal may have.
    static let poolSizes = 10...20

    static let opening = "Deal the pool."
    static let newDeal = "Deal a new pool, different from the last one."
    private static let cues: Set<String> = [opening, newDeal]

    /// What each letter costs: common ones little, rare ones a lot.
    static let prices: [Character: Int] = [
        "a": 1, "b": 3, "c": 3, "d": 2, "e": 1, "f": 4, "g": 2, "h": 4, "i": 1, "j": 8, "k": 5, "l": 1, "m": 3,
        "n": 1, "o": 1, "p": 3, "q": 10, "r": 1, "s": 1, "t": 1, "u": 1, "v": 4, "w": 4, "x": 8, "y": 4, "z": 10
    ]

    static let systemPrompt = """
    You are the banker in Letter auction, a word game you also play. When asked to deal, reply on one line with \
    fifteen capital letters separated by spaces, five or six of them vowels, mixing common letters with a few \
    rare ones like K, V, X, or Z, then “ | ” and five words those letters make. For example: \
    R A T E S L I N O P K Y U D E | slink, pure, tray, dote, ask. Deal a different pool every time. \
    Then the user and you take turns spending letters from the pool on English words, the user first. A letter \
    spent is gone for both of you, and a word may use only letters still in the pool, each no more often than \
    it is left. Rare letters are worth more. Reply to each word the user plays with one line. If it is a real \
    English word, write “OK: ” followed by a word of your own made from the letters left after the user's word. \
    If it isn't a real English word, write “NO: ” followed by a short, friendly reason. If you can't make a \
    word, write “OK: PASS”. Your earlier replies end with the letters that were left after your word. \
    No explanations, quotation marks, or Markdown.
    """

    static let invitation = "The banker deals a pool of letters. Take turns spending them on words, you first: a word banks what its letters are worth, and they’re gone for both of you. Type pass to close the bank."

    /// The banker's deal: the letters, and the words it says they make.
    struct Deal: Equatable {
        var letters: [Character]
        var words: [String] = []
    }

    /// A word played, and what it banked. A word of the banker's that the pool can't pay for banks nothing.
    struct Play: Equatable {
        var word: String
        var byYou: Bool
        var worth: Int
        var isPass = false
        var fits = true
    }

    struct Auction {
        var pool: [Character] = []
        var left: [Character] = []
        var suggestions: [String] = []
        var plays: [Play] = []
        var ending: GameOutcome?

        var you: Int { plays.filter(\.byYou).map(\.worth).reduce(0, +) }
        var banker: Int { plays.filter { !$0.byYou }.map(\.worth).reduce(0, +) }
    }

    /// The letters of a deal: "R A T E", "R, A, T, E", "Pool: R A T E", or "RATE".
    static func deal(from reply: String) -> Deal? {
        let lines = GameText.lines(reply).map(GameText.unwrapped)
        guard let first = lines.first else { return nil }
        var (shown, hidden) = GameText.split(first)
        if hidden == nil, lines.count > 1 { hidden = lines[1] }
        if let colon = shown.lastIndex(of: ":") { shown = String(shown[shown.index(after: colon)...]) }
        let tokens = shown.split { !$0.isLetter }.map { $0.lowercased() }
        let letters: [Character]
        if tokens.count > 1, tokens.allSatisfy({ $0.count == 1 }) {
            letters = tokens.compactMap(\.first)
        } else if tokens.count == 1 {
            letters = Array(tokens[0])
        } else {
            return nil
        }
        let vowels = letters.filter { "aeiou".contains($0) }
        guard poolSizes.contains(letters.count), vowels.count >= 3, letters.allSatisfy({ prices[$0] != nil }) else { return nil }
        let words = hidden?.split { !$0.isLetter }.map { cleanWord(String($0)) }.filter { $0.count >= 2 } ?? []
        return Deal(letters: letters, words: words)
    }

    /// One word, lower case, only the letters the pool can hold.
    static func cleanWord(_ text: String) -> String {
        String(text.lowercased().filter { prices[$0] != nil })
    }

    static func worth(of word: String) -> Int {
        word.reduce(0) { $0 + (prices[$1] ?? 0) }
    }

    /// The pool once `word` is paid for, or nil when it can't pay: a letter missing, or not enough of one.
    static func spending(_ word: String, from pool: [Character]) -> [Character]? {
        var left = pool
        for letter in word {
            guard let index = left.firstIndex(of: letter) else { return nil }
            left.remove(at: index)
        }
        return left
    }

    /// The letters `word` needs that the pool is short of, each once, in capitals.
    static func shortfall(of word: String, in pool: [Character]) -> [String] {
        var left = pool
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

    static func result(_ reason: String, you: Int, banker: Int) -> GameOutcome {
        if you > banker { return GameOutcome(text: "\(reason) You win, \(you) to \(banker).", youWon: true) }
        if you < banker { return GameOutcome(text: "\(reason) The banker wins, \(banker) to \(you).", youWon: false) }
        return GameOutcome(text: "\(reason) A draw, \(you) all.", youWon: nil)
    }

    static func review(_ turns: [ChatSession.Turn]) -> Auction {
        var auction = Auction()
        guard let deal = turns.first?.reply.flatMap(deal(from:)) else { return auction }
        auction.pool = deal.letters
        auction.left = deal.letters
        auction.suggestions = deal.words
        for turn in turns.dropFirst() {
            if let outcome = turn.outcome {
                auction.ending = outcome
                break
            }
            let yours = cleanWord(turn.question)
            if !yours.isEmpty, let left = spending(yours, from: auction.left) {
                auction.left = left
                auction.plays.append(Play(word: yours, byYou: true, worth: worth(of: yours)))
            }
            guard let reply = turn.reply else { continue }
            let word = cleanWord(GameText.words(GameText.verdict(of: reply).rest).first ?? "")
            if word.isEmpty || GameText.isGivingUp(word) {
                auction.plays.append(Play(word: "", byYou: false, worth: 0, isPass: true))
            } else if auction.plays.contains(where: { $0.word == word }) || word.count < 2 {
                auction.plays.append(Play(word: word, byYou: false, worth: 0, fits: false))
            } else if let left = spending(word, from: auction.left) {
                auction.left = left
                auction.plays.append(Play(word: word, byYou: false, worth: worth(of: word)))
            } else {
                auction.plays.append(Play(word: word, byYou: false, worth: 0, fits: false))
            }
        }
        if auction.ending == nil, turns.last?.isComplete == true {
            if auction.left.count < 2 {
                auction.ending = result("The pool is spent.", you: auction.you, banker: auction.banker)
            } else if auction.plays.count >= limit {
                auction.ending = result("Six words each, and the bank closes.", you: auction.you, banker: auction.banker)
            }
        }
        return auction
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let current = turns.since(cues) else { return GameState(phase: .modelMoves(cue: opening), status: title) }
        let auction = review(current)
        let status = auction.pool.isEmpty
            ? title
            : "\(auction.left.count) \(auction.left.count == 1 ? "letter" : "letters") left · You \(auction.you), Banker \(auction.banker)"
        if current.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        if let ending = auction.ending {
            return GameState(phase: .over(outcome: ending, rematch: Rematch(cue: newDeal, placeholder: "Press Return for a new deal…")), status: status)
        }
        return GameState(phase: .yourMove(placeholder: "A word from the pool…", hints: hints(for: auction)), status: status)
    }

    /// The words of the deal that the pool can still pay for, one per hint.
    static func hints(for auction: Auction) -> [String] {
        auction.suggestions
            .filter { word in spending(word, from: auction.left) != nil && !auction.plays.contains { $0.word == word } }
            .map { "Try “\($0.uppercased())”, worth \(worth(of: $0))." }
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let auction = review(turns.since(cues) ?? [])
        let words = GameText.words(GameText.firstLine(input))
        guard let first = words.first else { return .reject("Spend some letters on a word first.") }
        if words.count == 1, GameText.isGivingUp(first) {
            return .record(first, outcome: result("You closed the bank.", you: auction.you, banker: auction.banker))
        }
        guard words.count == 1 else { return .reject("One word at a time.") }
        let word = cleanWord(first)
        guard word.count >= 2 else { return .reject("Spend at least two letters.") }
        if auction.plays.contains(where: { $0.word == word }) {
            return .reject("“\(word.uppercased())” was played already. Try another.")
        }
        let short = shortfall(of: word, in: auction.left)
        guard short.isEmpty else {
            return .reject("The pool can’t pay for “\(word.uppercased())”: it’s short of \(letterList(short)).")
        }
        return .ask(word)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        if last.cue != nil {
            guard let deal = deal(from: reply) else {
                return .refuse("The banker fumbled the deal. Press Return for another.")
            }
            let letters = deal.letters.map { $0.uppercased() }.joined(separator: " ")
            return .accept(deal.words.isEmpty ? letters : "\(letters) | \(deal.words.joined(separator: ", "))")
        }
        let (accepted, rest) = GameText.verdict(of: reply)
        if accepted == false {
            return .refuse(rest.isEmpty
                ? "The banker says “\(last.question.uppercased())” isn’t a word. Try another."
                : "The banker says no: \(GameText.sentence(rest))")
        }
        let word = cleanWord(GameText.words(rest).first ?? "")
        let kept = "OK: \(word.isEmpty || GameText.isGivingUp(word) ? "PASS" : word)"
        // The letters left after the banker's word go with the reply, so the banker reads the pool next time.
        var settled = turns.since(cues) ?? []
        guard !settled.isEmpty else { return .accept(kept) }
        settled[settled.count - 1].answer = kept
        settled[settled.count - 1].isComplete = true
        let left = review(settled).left.map { $0.uppercased() }.joined(separator: " ")
        return .accept(left.isEmpty ? "\(kept) | nothing left" : "\(kept) | left: \(left)")
    }

    /// "Q", "Q and U", or "Q, U, and Z".
    private static func letterList(_ letters: [String]) -> String {
        let quoted = letters.map { "“\($0)”" }
        guard quoted.count > 2 else { return quoted.joined(separator: " and ") }
        return quoted.dropLast().joined(separator: ", ") + ", and " + quoted[quoted.count - 1]
    }

    /// The dealt pool with each letter's price, the letters spent faded.
    static func poolPieces(_ auction: Auction) -> [GameLine.Piece] {
        var left = auction.left
        var pieces: [GameLine.Piece] = []
        for (index, letter) in auction.pool.enumerated() {
            let isLeft = left.firstIndex(of: letter).map { left.remove(at: $0) } != nil
            let voice: GameLine.Voice = isLeft ? .model : .plain
            pieces.append(.init(text: (index == 0 ? "" : " ") + letter.uppercased(), voice: voice))
            pieces.append(.init(text: superscript(prices[letter] ?? 0), voice: .plain))
        }
        return pieces
    }

    private static func superscript(_ number: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return String(String(number).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    private static func label(for play: Play) -> String {
        if play.isPass { return "the banker passes" }
        if !play.fits { return "\(play.word.uppercased()), not in the pool" }
        return "\(play.word.uppercased()) +\(play.worth)"
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (index, current) in turns.rounds(cues).enumerated() {
            let auction = review(current)
            guard !auction.pool.isEmpty else { continue }
            lines.heading(index == 0 ? "The banker deals" : "New deal")
            lines.verse(poolPieces(auction))
            lines.verse(GameLines.chain(auction.plays.map { play in
                (label(for: play), play.byYou ? .you : play.fits && !play.isPass ? .model : .plain)
            }, separator: " · "))
            if let ending = auction.ending { lines.verdict(ending) }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let auctions = turns.rounds(cues).map(review).filter { !$0.pool.isEmpty }
        guard !auctions.isEmpty else { return nil }
        return auctions.map { auction in
            var text = ["Pool: \(auction.pool.map { $0.uppercased() }.joined(separator: " "))"]
            text += auction.plays.map { "\($0.byYou ? "You" : "Banker"): \(label(for: $0))" }
            if let ending = auction.ending { text.append(ending.text) }
            return text.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        let words = turns.rounds(cues).first.map(review)?.plays.filter { !$0.isPass && $0.fits }.map { $0.word.uppercased() } ?? []
        return words.isEmpty ? nil : words.prefix(3).joined(separator: " · ")
    }
}
