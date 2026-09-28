import Foundation

/// What an answer changed in the text its question was about, word by word: “Fix the grammar” about selected or
/// copied text, answered with the text put right. Show What Changed (⌘D) under the answer shows them in its
/// place, the words that went struck through in red and the ones that came in green (see `ChangesView`).
///
/// `ChatSession` looks for them when an answer ends (`find(in:against:)`). Only an answer that keeps most of the
/// text, in order, has them, so an explanation, a summary, or a translation has none. What is compared is the
/// whole answer, what follows a line that introduces the text (“Here's the corrected text:”), or a code block or
/// quote the answer put it in, whichever keeps the most of it. Like the rest of the chat, they live only in memory.
nonisolated struct TextChanges: Equatable, Sendable {
    enum Segment: Equatable, Sendable {
        /// In both texts.
        case same(String)
        /// Only in the text the question was about.
        case removed(String)
        /// Only in the answer.
        case added(String)
    }

    /// Both texts at once: what stayed, and in each place that changed, what went, then what came.
    let segments: [Segment]
    /// How many places changed: each run of words and marks that went or came between ones that stayed.
    let count: Int
    /// Somewhere only the spacing changed, such as a line break for a space. The new spacing shows, unmarked.
    let changesSpacing: Bool
    /// The text compared is code, from a code block in the answer, and shows in monospace.
    let isCode: Bool
    /// How much of the text stayed, from 0 to 1: the letters, digits, and marks kept, in order, out of those in
    /// the longer of the two.
    let similarity: Double

    /// How much of the text an answer has to keep, in order, to be the text changed rather than an answer about it.
    static let minimumSimilarity = 0.5
    /// The most words, spaces, and marks that may go or come, each counting once. Past it the answer is another
    /// text, and working out its changes would take long and a lot of memory.
    static let editLimit = 2_000
    /// The most pairs of a text and a part of the answer compared in full, those with the most words in common.
    private static let comparisonLimit = 4

    /// What the changes come to, beside Show Answer: “3 changes”, or that none were made.
    var summary: String {
        if count > 0 { return count == 1 ? "1 change" : "\(count.formatted()) changes" }
        return changesSpacing ? "Only the spacing changed" : "No changes"
    }

    /// The changes as VoiceOver reads them, which can't hear a line through a word.
    var spokenText: String {
        segments.map { segment in
            switch segment {
            case .same(let text): text
            case .removed(let text): " (removed: \(text)) "
            case .added(let text): " (added: \(text)) "
            }
        }.joined()
    }

    // MARK: Finding them

    /// What `answer` changed in the one of `originals` it keeps the most of, or nil when it keeps too little of
    /// any of them to be that text changed.
    static func find(in answer: String, against originals: [String]) -> TextChanges? {
        let parts = parts(of: answer)
        var seen: Set<String> = []
        let texts = originals.map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
        var pairs: [(text: String, part: Part, overlap: Double)] = []
        for text in texts {
            for part in parts { pairs.append((text, part, overlap(text, part.text))) }
        }
        // The most promising first; among equals, the first text and the first part.
        let promising = pairs.enumerated()
            .sorted { $0.element.overlap != $1.element.overlap ? $0.element.overlap > $1.element.overlap : $0.offset < $1.offset }
            .prefix(comparisonLimit)
            .map(\.element)
        var best: TextChanges?
        for (text, part, _) in promising {
            guard let changes = diff(from: text, to: part.text, isCode: part.isCode),
                  changes.similarity >= minimumSimilarity,
                  changes.similarity > best?.similarity ?? 0 else { continue }
            best = changes
        }
        return best
    }

    /// A part of an answer that may hold the text.
    struct Part: Equatable, Sendable {
        let text: String
        var isCode = false
    }

    /// The parts of an answer that may hold the text: all of it, what follows a first line that ends in a colon,
    /// and each code block and quote.
    static func parts(of answer: String) -> [Part] {
        let answer = normalized(answer)
        var parts = [Part(text: answer)]
        let paragraphs = answer.components(separatedBy: "\n\n")
        if paragraphs.count > 1, let intro = paragraphs.first, !intro.contains("\n"), intro.trimmed.hasSuffix(":") {
            parts.append(Part(text: paragraphs.dropFirst().joined(separator: "\n\n").trimmed))
        }
        parts += MarkdownBlock.codeBlocks(in: answer).map { Part(text: $0.code.trimmed, isCode: true) }
        parts += quotes(in: answer).map { Part(text: $0) }
        var seen: Set<String> = []
        return parts.filter { !$0.text.isEmpty && seen.insert($0.text).inserted }
    }

    /// The text of each Markdown quote, without its `>`s.
    private static func quotes(in text: String) -> [String] {
        var quotes: [String] = []
        var quote: [String] = []
        for line in text.components(separatedBy: "\n") + [""] {
            let rest = line.drop { $0 == " " }
            if line.count - rest.count <= 3, rest.first == ">" {
                let body = rest.dropFirst()
                quote.append(String(body.first == " " ? body.dropFirst() : body))
            } else if !quote.isEmpty {
                quotes.append(quote.joined(separator: "\n").trimmed)
                quote = []
            }
        }
        return quotes
    }

    /// Text with plain line breaks and without the spacing at its ends, as `SelectedText` keeps it.
    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmed
    }

    /// Roughly how much two texts have in common, whatever the order, to choose which to compare in full.
    private static func overlap(_ a: String, _ b: String) -> Double {
        var counts: [String: Int] = [:]
        for token in tokens(in: a) where !isSpace(token) { counts[token, default: 0] += 1 }
        var common = 0
        for token in tokens(in: b) where !isSpace(token) {
            guard let count = counts[token], count > 0 else { continue }
            counts[token] = count - 1
            common += token.count
        }
        let longer = max(characterCount(a), characterCount(b))
        return longer == 0 ? 1 : Double(common) / Double(longer)
    }

    // MARK: Comparing two texts

    /// What changed from `original` to `revised`, word by word, or nil when more than `editLimit` words, spaces,
    /// and marks went and came.
    static func diff(from original: String, to revised: String, isCode: Bool = false) -> TextChanges? {
        let old = tokens(in: original)
        let new = tokens(in: revised)
        var ids: [String: Int] = [:]
        func id(_ token: String) -> Int {
            if let id = ids[token] { return id }
            ids[token] = ids.count
            return ids.count - 1
        }
        guard let steps = steps(from: old.map(id), to: new.map(id), limit: editLimit) else { return nil }

        // Runs of tokens that stayed, and between them what went and what came.
        var regions: [(same: String?, removed: String, added: String)] = []
        var i = 0
        var j = 0
        for step in steps {
            switch step {
            case .keep:
                if let last = regions.last, let same = last.same {
                    regions[regions.count - 1].same = same + old[i]
                } else {
                    regions.append((old[i], "", ""))
                }
                i += 1
                j += 1
            case .remove, .add:
                if regions.last?.same != nil || regions.isEmpty { regions.append((nil, "", "")) }
                if step == .remove {
                    regions[regions.count - 1].removed += old[i]
                    i += 1
                } else {
                    regions[regions.count - 1].added += new[j]
                    j += 1
                }
            }
        }

        var segments: [Segment] = []
        var count = 0
        var changesSpacing = false
        var kept = 0
        func keep(_ text: String) {
            if case .same(let before)? = segments.last {
                segments[segments.count - 1] = .same(before + text)
            } else {
                segments.append(.same(text))
            }
        }
        for region in regions {
            if let same = region.same {
                keep(same)
                kept += characterCount(same)
            } else if !region.removed.isEmpty, !region.added.isEmpty, region.removed.allSatisfy(\.isWhitespace), region.added.allSatisfy(\.isWhitespace) {
                // Spacing for spacing: the text reads the same, laid out the new way.
                keep(region.added)
                changesSpacing = true
            } else {
                count += 1
                if !region.removed.isEmpty { segments.append(.removed(region.removed)) }
                if !region.added.isEmpty { segments.append(.added(region.added)) }
                kept += partialCredit(region.removed, region.added)
            }
        }
        let longer = max(characterCount(original), characterCount(revised))
        return TextChanges(
            segments: segments,
            count: count,
            changesSpacing: changesSpacing,
            isCode: isCode,
            similarity: longer == 0 ? 1 : min(1, Double(kept) / Double(longer))
        )
    }

    /// How much of a short word that changed stayed, so “recieve” for “receive” still counts as the text put
    /// right: the letters the two have in common, in order, whatever their case. Nothing for a longer stretch,
    /// which is rewritten rather than corrected.
    private static func partialCredit(_ removed: String, _ added: String) -> Int {
        let a = Array(removed.lowercased().filter { !$0.isWhitespace })
        let b = Array(added.lowercased().filter { !$0.isWhitespace })
        guard !a.isEmpty, !b.isEmpty, a.count <= 40, b.count <= 40 else { return 0 }
        var row = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var diagonal = 0
            for (index, y) in b.enumerated() {
                let above = row[index + 1]
                row[index + 1] = x == y ? diagonal + 1 : max(above, row[index])
                diagonal = above
            }
        }
        return row[b.count]
    }

    /// The characters that aren't spacing.
    private static func characterCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
    }

    // MARK: Words

    private enum Kind {
        case word
        case space
        /// A mark, a symbol, or a character of a script written without spaces, each a token of its own.
        case single
    }

    /// The text as the words, runs of spacing, and marks it is compared by. A word keeps an apostrophe inside it
    /// (“don't”); Chinese, Japanese, and Thai, written without spaces, go a character at a time.
    static func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var kind: Kind?
        for character in text {
            let next = Self.kind(of: character)
            if next == .single || next != kind, !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            kind = next
        }
        if !current.isEmpty { tokens.append(current) }

        var joined: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "'" || token == "’", let last = joined.last, isWord(last), index + 1 < tokens.count, isWord(tokens[index + 1]) {
                joined[joined.count - 1] = last + token + tokens[index + 1]
                index += 2
            } else {
                joined.append(token)
                index += 1
            }
        }
        return joined
    }

    private static func kind(of character: Character) -> Kind {
        if character.isWhitespace { return .space }
        guard let scalar = character.unicodeScalars.first else { return .single }
        let spaceless = scalar.properties.isIdeographic
            || (0x3040...0x30FF).contains(scalar.value) // Hiragana and Katakana
            || (0x0E00...0x0E7F).contains(scalar.value) // Thai
        if spaceless { return .single }
        return character.isLetter || character.isNumber || character == "_" ? .word : .single
    }

    private static func isWord(_ token: String) -> Bool {
        token.first.map { kind(of: $0) == .word } ?? false
    }

    private static func isSpace(_ token: String) -> Bool {
        token.first?.isWhitespace ?? true
    }

    // MARK: The shortest way from one to the other

    enum Step: Equatable, Sendable {
        /// The next item of both.
        case keep
        /// The next item of the first goes.
        case remove
        /// The next item of the second comes.
        case add
    }

    /// The fewest removals and additions that turn `a` into `b`, with every item that stays kept, in order, or
    /// nil when it takes more than `limit`. Myers's O(ND) difference algorithm, after the ends the two share, with
    /// every path kept inside the grid of the two.
    static func steps(from a: [Int], to b: [Int], limit: Int) -> [Step]? {
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let a = Array(a[prefix..<(a.count - suffix)])
        let b = Array(b[prefix..<(b.count - suffix)])
        let n = a.count
        let m = b.count
        guard abs(n - m) <= limit else { return nil }

        let most = min(n + m, limit)
        let offset = most + 1
        // The furthest x reached on each diagonal k = x - y, or -1 where no path inside the grid reaches.
        var v = [Int](repeating: -1, count: 2 * most + 3)
        // Before each round d, v for k in -d...d, starting at d * d, for finding the way back.
        var trace: [Int32] = []

        /// Where the furthest path on diagonal `k` in round `d` starts: down from `k + 1`, or right from
        /// `k - 1`, whichever reaches further without leaving the grid.
        func start(_ k: Int, _ d: Int, _ previous: (Int) -> Int) -> (x: Int, isDown: Bool)? {
            var best: (x: Int, isDown: Bool)?
            if k < d, previous(k + 1) >= 0, previous(k + 1) - k <= m {
                best = (previous(k + 1), true)
            }
            if k > -d, previous(k - 1) >= 0, previous(k - 1) + 1 <= n, previous(k - 1) + 1 > best?.x ?? -1 {
                best = (previous(k - 1) + 1, false)
            }
            return best
        }

        for d in 0...most {
            for k in -d...d { trace.append(Int32(v[offset + k])) }
            let snapshot = d * d + d
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if d == 0 {
                    x = 0
                } else if let from = start(k, d, { v[offset + $0] }) {
                    x = from.x
                } else {
                    v[offset + k] = -1
                    continue
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                guard x == n, y == m else { continue }

                // Back from the end, round by round, along the way each diagonal was reached.
                var steps: [Step] = []
                var round = d
                var base = snapshot
                while round > 0 {
                    let diagonal = x - y
                    let previous = { (k: Int) in Int(trace[base + k]) }
                    guard let from = start(diagonal, round, previous) else { return nil }
                    while x > from.x {
                        steps.append(.keep)
                        x -= 1
                        y -= 1
                    }
                    if from.isDown {
                        steps.append(.add)
                        y -= 1
                    } else {
                        steps.append(.remove)
                        x -= 1
                    }
                    round -= 1
                    base = round * round + round
                }
                while x > 0 {
                    steps.append(.keep)
                    x -= 1
                }
                return Array(repeating: .keep, count: prefix) + steps.reversed() + Array(repeating: .keep, count: suffix)
            }
        }
        return nil
    }
}
