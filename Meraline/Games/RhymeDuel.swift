import Foundation

/// Rhyme duel: a story told in rhyming couplets. The model writes a line that ends on a short word, you
/// finish the couplet with a line that rhymes with it, and the model carries the story on with a line that
/// ends on a new word; four lines each, so the last word is yours. Your line is a turn's question and the
/// model's line its answer; the opening turn has only a cue and the closing turn no answer.
///
/// A few words that rhyme with the model's ending travel after a bar in its reply ("The cat sat waiting by
/// the door | floor, more, four"), hidden. Hint shows one of them, and a line that ends on one of them
/// rhymes whatever this Mac's ear says.
nonisolated enum RhymeDuel: GameRules {
    static let title = "Rhyme Duel"
    static let summary = "Tell a story in rhyming couplets, four lines each"
    static let symbol = "music.mic"

    /// How many lines each side plays.
    static let linesPerSide = 4
    static let lineLimit = linesPerSide * 2

    static let systemPrompt = """
    You are playing a rhyme duel: you and the user tell a short story in verse, one line each, and you go first. \
    Every line you write ends on a short, common word of one syllable that is easy to rhyme with. \
    The user answers each of your lines with one that rhymes with it. \
    When asked to open, write the first line of a story; for a new duel, pick a new subject. \
    After each line the user writes, write the next line of the story: carry on from the user's line, in the same \
    spirit and about the same length, but end on a new word that rhymes with none of the lines so far. \
    Pick each ending word at random, and never end on the same word twice. \
    After your line, write “ | ” and six common words that rhyme with your last word, separated by commas. \
    For example: The cat sat waiting by the door | floor, more, four, shore, roar, core. \
    One line only: no preamble, no quotation marks, no Markdown, no explanation.
    """

    /// What the model is asked for its opening line. Nothing of yours is sent for it.
    static let opening = "Open the duel with your first line."
    static let rematchCue = "Start a new duel: open it with a fresh first line on a new subject."
    private static let cues: Set<String> = [opening, rematchCue]

    static let invitation = "The model starts a story. Finish each of its lines with a rhyme, and it carries on with a new word; four lines each. Stuck? Hint shows a rhyme."
    static let done = "Duel done, and the last word was yours."
    /// The nudge when the model's reply has no line in it: the opening is asked for again, your line comes back.
    static let noOpening = "The model had no line to open with. Press Return to ask again."
    static let lostTheThread = "The model lost the thread. Press Return to send your line again."

    /// A line of the model's: the verse, and the words it hid after the bar that rhyme with its last word.
    struct Verse: Equatable {
        var line: String
        var rhymes: [String] = []

        /// The reply as the game keeps it, which is also how the model sees it later.
        var kept: String { rhymes.isEmpty ? line : "\(line) | \(rhymes.joined(separator: ", "))" }
    }

    /// The footer's count: which line comes next, or that the duel is over.
    static func status(linesPlayed: Int) -> String {
        linesPlayed >= lineLimit ? "Duel done" : "Line \(linesPlayed + 1) of \(lineLimit)"
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let duel = turns.since(cues) else {
            return GameState(phase: .modelMoves(cue: opening), status: status(linesPlayed: 0))
        }
        let played = linesPlayed(in: duel)
        let status = status(linesPlayed: played)
        if duel.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        if played >= lineLimit {
            return GameState(phase: .over(outcome: GameOutcome(text: done, youWon: nil), rematch: Rematch(cue: rematchCue, placeholder: "Press Return for a rematch…")), status: status)
        }
        let previous = lastVerse(of: duel)
        let placeholder = previous.flatMap { rhymeWord(of: $0.line) }.map { "Rhyme with “\($0)”…" } ?? "Your line…"
        return GameState(phase: .yourMove(placeholder: placeholder, hints: previous.map(hints(for:)) ?? []), status: status)
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let duel = turns.since(cues) ?? []
        let line = line(from: input)
        guard !line.isEmpty else { return .reject("Write a line first.") }
        if !insisting, let previous = lastVerse(of: duel), let complaint = complaint(about: line, after: previous) {
            return .reject(complaint)
        }
        // The last word is yours: the model does not answer it.
        return linesPlayed(in: duel) >= lineLimit - 1 ? .record(line, outcome: nil) : .ask(line)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        let verse = verse(from: reply)
        guard verse.line.isEmpty else { return .accept(verse.kept) }
        return .refuse(turns.last?.question.isEmpty == false ? lostTheThread : noOpening)
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for (index, duel) in turns.rounds(cues).enumerated() {
            if index > 0 { lines.note("Rematch") }
            for turn in duel {
                if !turn.question.isEmpty { lines.you(turn.question) }
                if let reply = turn.reply { lines.model(verse(from: reply).line) }
            }
        }
        return lines.all
    }

    /// The poem: every line in order, a blank line between duels.
    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let duels = turns.rounds(cues)
            .map { duel in duel.flatMap { [$0.question, $0.reply.map { verse(from: $0).line } ?? ""] }.filter { !$0.isEmpty }.joined(separator: "\n") }
            .filter { !$0.isEmpty }
        return duels.isEmpty ? nil : duels.joined(separator: "\n\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        turns.first?.reply.map { verse(from: $0).line }
    }

    /// Lines played: yours as soon as it is sent, the model's once it is judged.
    private static func linesPlayed(in duel: [ChatSession.Turn]) -> Int {
        duel.reduce(0) { count, turn in count + (turn.question.isEmpty ? 0 : 1) + (turn.reply == nil ? 0 : 1) }
    }

    /// The model's last line, which your next one has to rhyme with.
    private static func lastVerse(of duel: [ChatSession.Turn]) -> Verse? {
        duel.last { $0.reply != nil }?.reply.map(verse(from:))
    }

    /// What Hint shows for a line of the model's, one at a time.
    static func hints(for verse: Verse) -> [String] {
        verse.rhymes.map { "Try ending your line on “\($0)”." }
    }

    /// The first non-empty line of what was typed or answered: a duel goes one line at a time.
    static func line(from text: String) -> String {
        GameText.firstLine(text)
    }

    /// The model's reply without the decoration models add: extra lines, wrapping quotes. The rhymes after
    /// the bar may sit on a line of their own; the line's own last word is not one of them.
    static func verse(from reply: String) -> Verse {
        let (shown, hidden) = GameText.split(reply)
        var line = line(from: shown)
        while line.count >= 2, let first = line.first, let last = line.last, quotes.contains(first), quotes.contains(last) {
            line = String(line.dropFirst().dropLast()).trimmed
        }
        let ending = rhymeWord(of: line).map(GameText.key)
        return Verse(line: line, rhymes: hidden.map(words(in:))?.filter { GameText.key($0) != ending } ?? [])
    }

    /// The rhymes after the bar: "floor, more, four", "Rhymes: floor, more", or "floor more four". Only
    /// single words count, each once.
    static func words(in list: String) -> [String] {
        var list = line(from: list)
        if let colon = list.lastIndex(of: ":") { list = String(list[list.index(after: colon)...]) }
        var parts = list.split { ",;·•/".contains($0) }.map(String.init)
        if parts.count == 1 { parts = parts[0].split(whereSeparator: \.isWhitespace).map(String.init) }
        var words: [String] = []
        for part in parts {
            let word = GameText.withoutEndPunctuation(GameText.unwrapped(part)).lowercased()
            guard word.contains(where: \.isLetter), word.allSatisfy({ $0.isLetter || apostrophes.contains($0) }),
                  !words.contains(word) else { continue }
            words.append(word)
        }
        return words
    }

    /// The word the next line has to rhyme with: the last word of a line, as typed, without punctuation.
    static func rhymeWord(of line: String) -> String? {
        let words = line.split { !$0.isLetter && !apostrophes.contains($0) }
        guard let word = words.last(where: { $0.contains(where: \.isLetter) }) else { return nil }
        return String(word.trimmingCharacters(in: CharacterSet(charactersIn: apostrophes)))
    }

    /// Why a line cannot go to the model yet, or nil when it can. A line after one with no word to rhyme
    /// with always can; the first line of a duel is never checked. A word the model gave as a rhyme counts
    /// as one, and so does a word that rhymes with one of those: "pour" answers "door" by way of "four".
    static func complaint(about line: String, after previous: Verse) -> String? {
        guard let target = rhymeWord(of: previous.line) else { return nil }
        guard let word = rhymeWord(of: line) else {
            return "End the line with a word that rhymes with “\(target)”."
        }
        if word.lowercased() == target.lowercased() {
            return "“\(target)” again? Find another rhyme for it, or send the line again as it is."
        }
        guard rhymes(word, with: target) || previous.rhymes.contains(where: { GameText.key($0) == GameText.key(word) || rhymes(word, with: $0) }) else {
            return "“\(word)” doesn’t rhyme with “\(target)”, not to my ear. Try another ending, or send the line again as it is."
        }
        return nil
    }

    /// Whether two words rhyme, by ear rather than by dictionary: the same rough ending sound, or the
    /// same last letters. Lenient on purpose; a game should let "heart" answer "art". The same word
    /// twice never counts.
    static func rhymes(_ word: String, with other: String) -> Bool {
        let a = word.lowercased().filter(\.isLetter)
        let b = other.lowercased().filter(\.isLetter)
        guard !a.isEmpty, !b.isEmpty, a != b else { return false }
        if rhymeKey(of: a) == rhymeKey(of: b) { return true }
        let length = min(a.count, b.count, 3)
        return length >= 2 && a.suffix(length) == b.suffix(length)
    }

    /// The rough sound of a word's ending: its last vowel sound, with the common spellings of one sound
    /// folded together, followed by the consonants after it. "rain", "plane", and "again" all come out
    /// as "An"; "light" and "kite" as "It". English spelling being what it is, this is a guess.
    static func rhymeKey(of word: String) -> String {
        var letters = Array(word.lowercased().filter(\.isLetter))
        guard !letters.isEmpty else { return "" }
        if letters.suffix(2) == ["y", "e"] { return "I" } // bye, dye, eye

        // A silent e after a consonant lengthens the vowel before it: plane, time, dove, June.
        var lengthened = false
        if letters.count > 2, letters.last == "e", !isVowel(letters, at: letters.count - 2), isVowel(letters, at: letters.count - 3) {
            lengthened = true
            letters.removeLast()
        }

        guard let end = letters.indices.last(where: { isVowel(letters, at: $0) }) else { return String(letters) }
        var start = end
        while start > 0, isVowel(letters, at: start - 1) { start -= 1 }
        var group = String(letters[start...end])
        var tail = String(letters[(end + 1)...])
        let afterVowel = letters[..<start].contains { "aeiou".contains($0) }

        if tail.first == "w" { group += "w"; tail.removeFirst() } // new, snow, law
        if tail.hasPrefix("gh") { group += "gh"; tail.removeFirst(2) } // light, weigh, though
        tail = collapsingDoubles(tail)

        return sound(of: group, before: tail, lengthened: lengthened, afterVowel: afterVowel) + tail
    }

    private static func sound(of group: String, before tail: String, lengthened: Bool, afterVowel: Bool) -> String {
        if lengthened, group.count == 1 { return group == "y" ? "I" : group.uppercased() } // plane, rhyme, June
        if let known = sounds[group] { return known }
        switch (group, tail.isEmpty) {
        case ("y", true): return afterVowel ? "E" : "I" // happy, sky
        case ("y", false): return "i" // gym
        case ("ie", true): return "I" // pie
        case ("ie", false): return "E" // piece
        case ("ou", true): return "U" // you
        case ("ou", false), ("ow", false): return "OW" // loud, down
        case ("ow", true): return "O" // snow
        default: break
        }
        if group.count == 1, tail.isEmpty { return group.uppercased() } // go, be, hi
        if group.count == 1, tail.first == "r", ["e", "i", "u"].contains(group) { return "ə" } // her, fur, sir
        return group
    }

    private static let apostrophes = "'’"
    private static let quotes: Set<Character> = ["\"", "“", "”", "'", "‘", "’", "«", "»"]

    /// Spellings that share a sound, whatever follows them.
    private static let sounds: [String: String] = [
        "ai": "A", "ay": "A", "ei": "A", "ey": "A", "ae": "A", "aigh": "A", "eigh": "A",
        "ee": "E", "ea": "E",
        "igh": "I", "uy": "I",
        "oa": "O", "oe": "O", "ough": "O", "au": "O", "aw": "O",
        "oo": "U", "ue": "U", "ew": "U", "ui": "U",
        "oi": "OY", "oy": "OY"
    ]

    /// Vowels, with y counting as one unless it starts a syllable: "sky" and "gym", but not "yes" or "beyond".
    private static func isVowel(_ letters: [Character], at index: Int) -> Bool {
        let letter = letters[index]
        if "aeiou".contains(letter) { return true }
        guard letter == "y", index > 0 else { return false }
        return index == letters.count - 1 || !"aeiou".contains(letters[index + 1])
    }

    /// "ss" and "ll" sound like "s" and "l".
    private static func collapsingDoubles(_ text: String) -> String {
        var result = ""
        for character in text where result.last != character { result.append(character) }
        return result
    }
}
