import AppKit
import Synchronization

/// Words on this Mac, for a game that judges them itself. macOS's spell checker knows everyday words and their
/// forms in most of the answer languages; the word list every Mac has (/usr/share/dict/words, Webster's Second)
/// holds English base words, which a few common endings turn into the forms it leaves out. Both are only read.
nonisolated enum WordCheck {
    /// Whether `word` is a word in `language`, as the spell checker says, or nil when it has no dictionary for
    /// the language, and then a game takes the word on trust.
    static func isWord(_ word: String, in language: AnswerLanguage) -> Bool? {
        let word = word.lowercased()
        guard word.count >= 2, let code = spellChecker(for: language) else { return nil }
        let miss = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: code, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return miss.location == NSNotFound
    }

    /// The spell checker's name for a language, when it has a dictionary for it.
    static func spellChecker(for language: AnswerLanguage) -> String? {
        let code = switch language {
        case .english: "en"
        case .czech: "cs"
        case .slovak: "sk"
        case .croatian: "hr"
        case .danish: "da"
        case .dutch: "nl"
        case .finnish: "fi"
        case .french: "fr"
        case .german: "de"
        case .greek: "el"
        case .hungarian: "hu"
        case .italian: "it"
        case .japanese: "ja"
        case .korean: "ko"
        case .norwegian: "nb"
        case .polish: "pl"
        case .portuguese: "pt_PT"
        case .romanian: "ro"
        case .russian: "ru"
        case .chinese: "zh"
        case .slovenian: "sl"
        case .spanish: "es"
        case .swedish: "sv"
        case .turkish: "tr"
        case .ukrainian: "uk"
        }
        return NSSpellChecker.shared.availableLanguages.contains(code) ? code : nil
    }

    /// The longest English words `letters` make, longest first, each letter used no more often than it is there:
    /// words of the word list and their common forms, as the spell checker knows them. Worked out once for a set
    /// of letters.
    static func longestWords(from letters: [Character], count: Int = 3) -> [String] {
        let key = String(letters.sorted())
        if let known = found.withLock({ $0[key] }) { return known }
        let have = Signature(letters)
        var candidates: Set<String> = []
        for entry in list where entry.signature.fits(in: have) {
            candidates.insert(entry.word)
            for form in forms(of: entry.word) where Signature(Array(form)).fits(in: have) { candidates.insert(form) }
        }
        var words: [String] = []
        for word in candidates.sorted(by: { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }) where isWord(word, in: .english) == true {
            words.append(word)
            if words.count == count { break }
        }
        found.withLock { $0[key] = words }
        return words
    }

    /// Endings the word list leaves off: plurals, the past, “-ing”, and a few more.
    private static func forms(of word: String) -> [String] {
        var forms = ["s", "es", "ed", "er", "ers", "ing", "est", "ly"].map { word + $0 }
        if word.hasSuffix("e") {
            let stem = String(word.dropLast())
            forms += ["d", "r", "rs"].map { word + $0 } + ["ing", "ings"].map { stem + $0 }
        }
        return forms
    }

    /// How many of each letter a word takes, two bits a letter, and which letters it takes at all.
    private struct Signature {
        var mask: UInt32 = 0
        var counts: UInt64 = 0
        /// A word takes at most three of a letter, since no round draws more.
        var isValid = true

        init(_ letters: [Character]) {
            for letter in letters {
                guard let ascii = letter.asciiValue, (97...122).contains(ascii) else {
                    isValid = false
                    return
                }
                let index = Int(ascii - 97)
                guard (counts >> (2 * index)) & 3 < 3 else {
                    isValid = false
                    return
                }
                counts += 1 << (2 * index)
                mask |= 1 << index
            }
        }

        func fits(in letters: Signature) -> Bool {
            guard isValid, mask & ~letters.mask == 0 else { return false }
            var remaining = mask
            while remaining != 0 {
                let index = remaining.trailingZeroBitCount
                if (counts >> (2 * index)) & 3 > (letters.counts >> (2 * index)) & 3 { return false }
                remaining &= remaining - 1
            }
            return true
        }
    }

    private struct Entry {
        let word: String
        let signature: Signature
    }

    /// The word list's lower-case words of three to nine letters, read when a game first needs them.
    private static let list: [Entry] = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        var entries: [Entry] = []
        for line in text.split(separator: "\n") where (3...9).contains(line.utf8.count) {
            guard line.utf8.allSatisfy({ (97...122).contains($0) }) else { continue }
            let signature = Signature(Array(line))
            if signature.isValid { entries.append(Entry(word: String(line), signature: signature)) }
        }
        return entries
    }()

    private static let found = Mutex<[String: [String]]>([:])
}
