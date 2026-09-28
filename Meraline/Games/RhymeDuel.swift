import Foundation

/// Rhyme duel: a story told in rhyming couplets, opened by you or by the model. Whoever opens sets each
/// rhyme: a line that ends on a word, which the other finishes the couplet with a line rhyming with, before
/// the setter carries the story on with a line that ends on a new word. Four lines each, so the last word is
/// the answerer's. Your line is a turn's question and the model's line its answer; the model's opening turn
/// has only a cue, yours a cue and your line, and your closing line, when you answer, no answer.
///
/// Each duel's story and the words each of the model's lines may end on are drawn on this Mac: a model left to
/// choose opens every duel alike and ends on the same few words. The words come from `families`, one rhyming
/// sound at a time, never one a line of the duel has ended on. They are English, so a duel in another language
/// draws only its story, and its rhymes are the model's.
///
/// A few words that rhyme with the model's ending travel after a bar in its reply ("The cat sat waiting by
/// the door | floor, more, four"), hidden. Hint shows one of them or of the ending's family, and a line that
/// ends on one of them rhymes whatever this Mac's ear says.
nonisolated enum RhymeDuel: GameRules {
    static let title = "Rhyme Duel"
    static let summary = "Tell a story in rhyming couplets, four lines each"
    static let symbol = "music.mic"

    /// How many lines each side plays.
    static let linesPerSide = 4
    static let lineLimit = linesPerSide * 2

    static let systemPrompt = """
    You are playing a rhyme duel: you and the user tell a short story in verse, one line each, taking turns. \
    Whoever opens the duel sets each rhyme, and the other answers it. \
    When you open, the user answers each of your lines with one that rhymes with it, and after each line the user \
    writes, you carry the story on with a line that ends on a new word, one that rhymes with none of the lines so far. \
    When the user opens, answer each of the user's lines with the next line of the story, rhyming with it. \
    When asked to open, write the first line of a story about the subject the message gives, in its mood. \
    Carry on from the user's line, in the same spirit and about the same length. \
    Each message names a few words your line may end on: end it on whichever of them suits the story best. \
    When a message names none, end on a short, common word of one syllable that is easy to rhyme with, never the same word twice. \
    After your line, write “ | ” and six common words that rhyme with your last word, separated by commas. \
    For example: The cat sat waiting by the door | floor, more, four, shore, roar, core. \
    One line only: no preamble, no quotation marks, no Markdown, no explanation.
    """

    /// What the model is asked for its opening line. Nothing of yours is sent for it.
    static let opening = "Open the duel with your first line."
    static let rematchCue = "Start a new duel: open it with a fresh first line on a new subject."
    /// What goes with your opening line: you set the rhymes this duel.
    static let yourOpening = "The user opens this duel with the first line below, so the user sets each rhyme: answer each of their lines with the next line of the story, rhyming with it."
    private static let cues: Set<String> = [opening, rematchCue, yourOpening]

    static let invitation = "Write the first line of a story, or let the model start. Whoever starts sets each rhyme and the other answers it; four lines each. Stuck? Hint shows a rhyme."
    static let done = "Duel done, and the last word was yours."
    static let doneByModel = "Duel done, and the model had the last word."
    static let randomButton = "Random Rhyme"
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

    /// A duel the model opens gets a story to tell and the words its first line may end on; your line, the words
    /// the model's next may end on. The words share a sound that no line of the duel has ended on yet, nor of the
    /// chat's earlier duels while there are sounds left. In a duel you opened, the model's line answers yours,
    /// so the words rhyme with your line instead.
    static func aside(for turn: ChatSession.Turn, after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> String? {
        let opens = turn.cue.map(cues.contains) == true
        let duel = opens ? [turn] : (turns.since(cues) ?? []) + [turn]
        if youSetRhymes(in: duel) { return rhyming(with: turn.question, in: language, dice: &dice) }
        guard language == .english else { return opens ? "This duel’s story: \(premise(dice: &dice))." : nil }
        let ending = rhymeWord(of: turn.question).map { [$0] } ?? []
        let inDuel = families(heardIn: duel.dropLast().flatMap(endings(of:)) + ending)
        let inChat = families(heardIn: turns.flatMap(endings(of:)) + ending)
        let open = families.indices.filter { !inDuel.contains($0) }
        guard let family = dice.pick(from: open.isEmpty ? Array(families.indices) : open, preferring: { !inChat.contains($0) }) else {
            return nil
        }
        let words = dice.deal(offered, from: families[family])
        let end = "\(offering)\(words.joined(separator: ", "))."
        guard opens else { return end }
        return "This duel’s story: \(premise(dice: &dice)). \(end)"
    }

    /// How many words of a family the model is offered for a line.
    static let offered = 3

    /// How an aside offers the words a line may end on.
    private static let offering = "End your line on one of these words: "

    /// The words the model's line may end on to answer your line: others of its ending's family, in English.
    private static func rhyming(with line: String, in language: AnswerLanguage, dice: inout GameDice) -> String? {
        guard let word = rhymeWord(of: line) else { return nil }
        let key = GameText.key(word)
        guard language == .english, let family = family(of: word) else { return "End your line on a word that rhymes with “\(word)”." }
        let words = dice.deal(offered, from: family.filter { $0 != key })
        return "\(offering)\(words.joined(separator: ", "))."
    }

    /// Whether you opened the duel, and so set each rhyme while the model answers it.
    static func youSetRhymes(in duel: [ChatSession.Turn]) -> Bool {
        duel.first?.cue == yourOpening
    }

    /// A story to tell: someone, somewhere, something happening, and a mood, such as “a retired pirate in a
    /// laundromat loses a bet. Make it spooky”.
    static func premise(dice: inout GameDice) -> String {
        let who = heroes.randomElement(using: &dice) ?? heroes[0]
        let place = places.randomElement(using: &dice) ?? places[0]
        let event = events.randomElement(using: &dice) ?? events[0]
        let mood = moods.randomElement(using: &dice) ?? moods[0]
        return "\(who) \(place) \(event). Make it \(mood)"
    }

    /// The words the lines of a duel ended on, yours and the model's.
    private static func endings(of turn: ChatSession.Turn) -> [String] {
        [rhymeWord(of: turn.question), turn.reply.flatMap { rhymeWord(of: verse(from: $0).line) }].compactMap { $0 }
    }

    /// The families, by number, that the words sound like: those they are in or rhyme with a word of.
    private static func families(heardIn words: [String]) -> Set<Int> {
        var heard: Set<Int> = []
        for word in words {
            let letters = word.lowercased().filter(\.isLetter)
            guard !letters.isEmpty else { continue }
            if let known = familyIndex[letters] { heard.insert(known) }
            let key = rhymeKey(of: letters)
            for (number, family) in familySounds.enumerated() where !heard.contains(number) {
                if family.contains(where: { $0.word != letters && rhymes(letters, key, with: $0.word, $0.key) }) { heard.insert(number) }
            }
        }
        return heard
    }

    /// Each family's words with their rough sound, worked out once.
    private static let familySounds: [[(word: String, key: String)]] = families.map { $0.map { ($0, rhymeKey(of: $0)) } }

    /// The family a word is in, if any.
    static func family(of word: String) -> [String]? {
        familyIndex[GameText.key(word)].map { families[$0] }
    }

    private static let familyIndex: [String: Int] = {
        var index: [String: Int] = [:]
        for (number, family) in families.enumerated() {
            for word in family { index[word] = number }
        }
        return index
    }()

    /// The model opens a duel you leave to it, the first with `opening`.
    static func opener(after turns: [ChatSession.Turn], in language: AnswerLanguage, dice: inout GameDice) -> GameOpener {
        .ask(turns.isEmpty ? opening : rematchCue)
    }

    /// Your first line opens the duel, and you set the rhymes.
    static func open(with input: String, after turns: [ChatSession.Turn]) -> GameMove {
        let line = line(from: input)
        return line.isEmpty ? .reject("Write a line first.") : .open(line, cue: yourOpening)
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let duel = turns.since(cues) else {
            let opening = GameOpening(placeholder: "Write the first line of a story, or press Return for a random one…", button: randomButton)
            return GameState(phase: .opening(opening), status: status(linesPlayed: 0))
        }
        let played = linesPlayed(in: duel)
        let status = status(linesPlayed: played)
        if duel.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        let youSet = youSetRhymes(in: duel)
        if played >= lineLimit {
            let next = GameOpening(placeholder: "Write the first line of a new duel, or press Return for a random one…", button: randomButton)
            return GameState(phase: .over(outcome: GameOutcome(text: youSet ? doneByModel : done, youWon: nil), next: next), status: status)
        }
        if youSet { return GameState(phase: .yourMove(placeholder: "Carry the story on, ending on a new sound…"), status: status) }
        let previous = lastVerse(of: duel)
        let placeholder = previous.flatMap { rhymeWord(of: $0.line) }.map { "Rhyme with “\($0)”…" } ?? "Your line…"
        return GameState(phase: .yourMove(placeholder: placeholder, hints: previous.map(hints(for:)) ?? []), status: status)
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let duel = turns.since(cues) ?? []
        let line = line(from: input)
        guard !line.isEmpty else { return .reject("Write a line first.") }
        if youSetRhymes(in: duel) {
            if !insisting, let complaint = complaint(aboutNewSound: line, in: duel) { return .reject(complaint) }
            // The model answers every line of yours, the last one too.
            return .ask(line)
        }
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
        guard let first = turns.first else { return nil }
        return first.question.isEmpty ? first.reply.map { verse(from: $0).line } : first.question
    }

    /// Lines played: yours as soon as it is sent, the model's once it is judged.
    private static func linesPlayed(in duel: [ChatSession.Turn]) -> Int {
        duel.reduce(0) { count, turn in count + (turn.question.isEmpty ? 0 : 1) + (turn.reply == nil ? 0 : 1) }
    }

    /// The model's last line, which your next one has to rhyme with, with the words known to rhyme with it: those
    /// it hid after the bar, and the rest of its ending's family when the line ended on one of them as offered.
    private static func lastVerse(of duel: [ChatSession.Turn]) -> Verse? {
        guard let turn = duel.last(where: { $0.reply != nil }), let reply = turn.reply else { return nil }
        let verse = verse(from: reply)
        guard turn.aside?.contains(offering) == true else { return verse }
        return Verse(line: verse.line, rhymes: rhymes(for: verse))
    }

    /// What Hint shows for a line of the model's, one at a time.
    static func hints(for verse: Verse) -> [String] {
        verse.rhymes.map { "Try ending your line on “\($0)”." }
    }

    /// The words known to rhyme with a line of the model's: those it hid after the bar, then the rest of its
    /// ending's family.
    static func rhymes(for verse: Verse) -> [String] {
        guard let ending = rhymeWord(of: verse.line).map(GameText.key) else { return verse.rhymes }
        var words = verse.rhymes
        for word in family(of: ending) ?? [] where word != ending && !words.contains(where: { GameText.key($0) == word }) {
            words.append(word)
        }
        return words
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
    /// with always can; the first line of a duel is never checked. A word known to rhyme with the line (see
    /// `lastVerse(of:)`) counts as one, and so does a word that rhymes with one of those: "pour" answers
    /// "door" by way of "four".
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

    /// Why a line of yours that sets a rhyme cannot go yet: it ends on a sound a line of the duel has, or on no word.
    static func complaint(aboutNewSound line: String, in duel: [ChatSession.Turn]) -> String? {
        guard let word = rhymeWord(of: line) else { return "End the line with a word, for the model to rhyme with." }
        let key = GameText.key(word)
        guard let heard = duel.flatMap(endings(of:)).first(where: { GameText.key($0) == key || rhymes(word, with: $0) }) else { return nil }
        return "“\(word)” sounds like “\(heard)”, a line’s end already. End on a new sound, or send the line again as it is."
    }

    /// Whether two words rhyme, by ear rather than by dictionary: the same rough ending sound, or the
    /// same last letters, accents aside ("rád" and "hrad"). Lenient on purpose; a game should let "heart"
    /// answer "art". The same word twice never counts.
    static func rhymes(_ word: String, with other: String) -> Bool {
        let a = GameText.folded(word.lowercased()).filter(\.isLetter)
        let b = GameText.folded(other.lowercased()).filter(\.isLetter)
        guard !a.isEmpty, !b.isEmpty, a != b else { return false }
        return rhymes(a, rhymeKey(of: a), with: b, rhymeKey(of: b))
    }

    /// The same for two different words in lower-case letters, with their sounds worked out already.
    private static func rhymes(_ a: String, _ aKey: String, with b: String, _ bKey: String) -> Bool {
        if aKey == bKey { return true }
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

    /// Words of one syllable that rhyme, a family to a sound, each sound its own: the model's lines end on them.
    /// Every family has enough members for three to offer and a few left over for Hint.
    static let families: [[String]] = [
        ["day", "way", "play", "stay", "gray", "clay", "tray", "sway", "pay", "say"],
        ["tree", "sea", "free", "key", "knee", "bee", "tea", "three", "glee", "flea"],
        ["night", "light", "bright", "kite", "white", "bite", "flight", "sight", "fright", "height"],
        ["door", "floor", "more", "shore", "roar", "four", "core", "store", "snore", "pour"],
        ["gold", "cold", "bold", "told", "fold", "old", "hold", "sold", "scold"],
        ["ring", "king", "sing", "wing", "spring", "thing", "string", "swing", "bring"],
        ["bell", "shell", "well", "spell", "smell", "tell", "yell", "fell", "cell"],
        ["ball", "wall", "hall", "fall", "call", "tall", "small", "stall"],
        ["cake", "lake", "snake", "wake", "shake", "bake", "flake", "rake"],
        ["rain", "train", "chain", "plane", "lane", "brain", "grain", "cane", "pain", "crane"],
        ["moon", "spoon", "soon", "tune", "noon", "croon", "dune", "prune"],
        ["cat", "hat", "bat", "mat", "flat", "rat", "chat", "sat"],
        ["dog", "frog", "log", "fog", "jog", "bog", "clog", "hog"],
        ["bed", "red", "bread", "head", "shed", "fed", "sled", "thread"],
        ["pot", "hot", "knot", "spot", "lot", "dot", "shot", "plot", "trot"],
        ["bug", "mug", "rug", "hug", "plug", "jug", "tug", "slug"],
        ["nose", "rose", "hose", "toes", "froze", "those", "knows", "goes"],
        ["ear", "fear", "near", "clear", "deer", "year", "cheer", "gear", "steer", "here"],
        ["chair", "hair", "air", "stair", "fair", "pair", "care", "square", "dare", "share"],
        ["heart", "art", "cart", "start", "part", "smart", "dart", "chart"],
        ["dark", "park", "bark", "shark", "spark", "mark", "stark", "lark"],
        ["town", "crown", "down", "gown", "brown", "frown", "clown", "drown"],
        ["sound", "ground", "round", "found", "hound", "pound", "bound", "mound"],
        ["ride", "side", "wide", "tide", "hide", "slide", "pride", "guide", "bride"],
        ["line", "mine", "fine", "pine", "wine", "sign", "shine", "nine", "spine", "vine"],
        ["time", "rhyme", "lime", "climb", "dime", "chime", "crime", "slime"],
        ["smile", "mile", "pile", "tile", "file", "while", "style"],
        ["wave", "cave", "brave", "grave", "save", "gave", "shave", "crave"],
        ["gate", "late", "plate", "skate", "date", "great", "wait", "eight", "straight", "state"],
        ["fast", "past", "last", "cast", "blast", "mast", "vast"],
        ["best", "nest", "rest", "test", "west", "chest", "guest", "vest", "quest"],
        ["stick", "quick", "brick", "trick", "kick", "pick", "thick", "click"],
        ["rock", "clock", "sock", "lock", "dock", "block", "knock", "shock", "flock"],
        ["book", "cook", "hook", "look", "nook", "shook", "brook", "took"],
        ["boat", "coat", "goat", "note", "float", "throat", "wrote", "vote"],
        ["blue", "shoe", "glue", "true", "new", "flew", "zoo", "crew", "stew", "grew"],
        ["sand", "hand", "land", "band", "stand", "grand", "brand", "planned"],
        ["bank", "tank", "plank", "thank", "drank", "sank", "blank", "prank"],
        ["jump", "bump", "lump", "pump", "stump", "thump", "grump"],
        ["hill", "still", "will", "chill", "spill", "mill", "fill", "drill", "thrill"],
        ["snow", "glow", "slow", "show", "grow", "go", "toe", "know", "flow", "crow"],
        ["star", "car", "far", "jar", "bar", "scar", "are", "tar"],
        ["feet", "street", "sweet", "heat", "beat", "seat", "meet", "treat", "wheat"],
        ["dream", "stream", "team", "cream", "beam", "steam", "seem", "scream"],
        ["face", "space", "race", "place", "lace", "chase", "case", "base", "grace"],
        ["room", "broom", "doom", "bloom", "zoom", "gloom", "boom", "groom"],
        ["ship", "trip", "lip", "drip", "flip", "slip", "grip", "tip", "chip"],
        ["top", "shop", "drop", "mop", "hop", "stop", "pop", "crop"],
        ["ten", "pen", "hen", "men", "then", "when", "den", "glen"],
        ["turn", "burn", "learn", "fern", "churn", "earn", "stern"],
        ["bird", "word", "heard", "third", "herd", "nerd", "stirred"],
        ["find", "mind", "kind", "blind", "grind", "signed"],
        ["out", "shout", "doubt", "scout", "sprout", "trout", "snout", "pout"],
        ["sun", "fun", "run", "one", "done", "bun", "won", "spun", "ton"],
        ["dress", "mess", "guess", "less", "press", "chess", "bless"],
        ["tail", "mail", "sail", "snail", "whale", "pale", "trail", "nail"],
        ["meal", "wheel", "steel", "heel", "deal", "feel", "peel", "seal"],
        ["pool", "cool", "school", "fool", "tool", "stool", "rule", "mule"],
        ["joke", "smoke", "oak", "cloak", "poke", "woke", "broke", "spoke"],
        ["bang", "sang", "rang", "hang", "fang", "gang", "slang"],
        ["drum", "hum", "plum", "gum", "thumb", "crumb", "come", "some"]
    ]

    /// Who a duel's story is about.
    static let heroes = [
        "a retired pirate", "a nervous dragon", "a tiny robot", "a lighthouse keeper", "a lost penguin",
        "a sleepy wizard", "a grumpy cat", "a young knight", "a ghost afraid of the dark", "a very old tortoise",
        "a chef who can’t taste", "a clumsy astronaut", "a talking teapot", "a shy giant", "a runaway kite",
        "a detective duck", "a goat who plays chess", "a lonely scarecrow", "a traveling musician", "a stubborn mule",
        "a forgetful king", "a brave little mouse", "a fox in a borrowed coat", "a queen who hates hats",
        "a bored vampire", "a mermaid who can’t swim", "a firefighter on a day off", "a squirrel with a secret",
        "a night-shift museum guard", "a dancing bear", "a homesick alien", "a reluctant hero", "a pair of old boots",
        "a broken clock", "a bus driver", "a grandmother who races cars", "a dog who wants to fly",
        "an owl who can’t stay up late", "a parrot who tells tales", "a sock without its pair", "a tired dentist",
        "a magician’s rabbit", "a worried farmer", "a wandering troll", "a runaway balloon", "a champion snail",
        "a baker with a sweet tooth", "a spy who can’t whisper"
    ]

    /// Where it happens.
    static let places = [
        "in a laundromat", "on the moon", "at a school dance", "in a submarine", "at the bottom of the sea",
        "in a snowed-in cabin", "on a night train", "in a museum after closing", "at a busy airport",
        "in a haunted library", "on a tiny island", "at a county fair", "in a bakery", "on a rooftop",
        "in a jungle", "at a wedding", "in the desert", "in thick fog", "at a bus stop", "on a pirate ship",
        "in a castle kitchen", "at the zoo", "in a garden shed", "on a mountaintop", "in a traffic jam",
        "at a football match", "in a cave", "on a frozen lake", "at a night market", "in a stuck elevator",
        "on a farm", "in a toy shop", "at a birthday party", "on a sinking raft", "in a lighthouse",
        "at a spelling bee", "in outer space", "at the dentist", "in a thunderstorm", "at a flea market",
        "in a dark forest", "on a camping trip", "at a talent show", "in a candy factory", "deep underground",
        "on a hot-air balloon", "at the North Pole", "in a hotel lobby"
    ]

    /// What happens.
    static let events = [
        "loses a bet", "finds a door that wasn’t there yesterday", "has to bake a cake for a king",
        "forgets something important", "is chased by bees", "wins a prize by mistake", "gets stuck",
        "falls in love", "meets their double", "tries to keep a secret", "starts a band", "finds a treasure map",
        "oversleeps on the big day", "learns to dance", "tries to catch a thief", "gets a strange letter",
        "loses their shadow", "swaps places with a friend", "has one wish left", "runs for mayor",
        "adopts a very large pet", "misses the last train", "cooks dinner for a crowd", "is late for everything",
        "plants a magic seed", "can’t stop sneezing", "hears a strange noise", "builds a rocket",
        "tells one lie too many", "gets hiccups before a speech", "wakes up famous", "finds a message in a bottle",
        "breaks something precious", "turns invisible for a day", "gets hopelessly lost", "enters a contest",
        "finds a baby dragon", "hides from the rain", "loses the keys", "throws a surprise party"
    ]

    /// The mood it is told in: “Make it …”.
    static let moods = [
        "funny", "spooky", "heroic", "gentle", "dramatic", "silly", "mysterious", "cozy", "sad but hopeful", "grand", "cheeky"
    ]
}
