import Foundation
import FoundationModels
import NaturalLanguage

/// Two or three questions to ask next, suggested under the last answer (see `FollowUpChips`). They are worked out
/// on this Mac, never by the provider: by Apple's on-device model when Apple Intelligence is on, and otherwise from
/// the answer's shape (its code, the terms it sets in bold or starts its list items with) and the kind of question
/// it answered. They live in memory only (`ChatSession.followUps`) and in no turn, so Recent Chats, Copy, and the
/// next request never carry them.
nonisolated enum FollowUps {
    /// The most shown at once.
    static let limit = 3
    /// The fewest worth showing: one alone reads like the answer's last line.
    static let minimum = 2
    /// How much of the question and the answer the on-device model reads. Its window holds about 4,000 tokens,
    /// the instructions and its reply included, and a character can be a token in Chinese or Japanese.
    static let questionLimit = 400
    static let answerLimit = 2_000

    /// What the suggestions are worked out from.
    struct Request: Equatable, Sendable {
        /// The question as typed; empty for one asked about a picture, a file, or selected text alone.
        let question: String
        let answer: String
        /// The chat's questions so far, which no suggestion repeats.
        var asked: [String] = []
        var language: AnswerLanguage = .english
    }

    /// The on-device model's suggestions when it can make them, else those drawn from the answer's shape, which
    /// are English, so an answer in another language gets none. The test host never asks the on-device model.
    static func suggest(_ request: Request) async -> [String] {
        if AppleIntelligenceClient.isAvailable, !MeralineApp.isHostingTests {
            do {
                let suggested = cleaned(try await onDevice(request), for: request)
                if !suggested.isEmpty { return suggested }
                Log.chat.info("The on-device model suggested no usable follow-ups")
            } catch is CancellationError {
                return []
            } catch {
                Log.chat.error("On-device follow-ups failed: \(error.localizedDescription)")
            }
        }
        return drawn(for: request)
    }

    // MARK: On-device

    @Generable
    struct Suggestions {
        @Guide(description: "What the person might ask next, each as they would type it", .count(3))
        var questions: [String]
    }

    static func onDevice(_ request: Request) async throws -> [String] {
        let session = LanguageModelSession(instructions: instructions(in: request.language))
        let response = try await session.respond(
            to: prompt(for: request),
            generating: Suggestions.self,
            options: GenerationOptions(temperature: 0.7)
        )
        return response.content.questions
    }

    static func instructions(in language: AnswerLanguage) -> String {
        """
        You suggest what someone might ask an assistant next, after reading its answer to their question. \
        Write each suggestion as they would type it: a short question or request in their own words, under ten \
        words. Each follows on from something specific in the answer, and each goes a different way. Each makes \
        sense on its own, read by the assistant as the next message of the chat. Never repeat their question, \
        never ask to shorten, expand, simplify, or reformat the answer, and never speak to them.

        \(language == .english ? "Write them in the language of the answer." : "Write them in \(language.name).")
        """
    }

    /// The question and the answer, each cut to what the model's window holds.
    static func prompt(for request: Request) -> String {
        let question = request.question.trimmed
        let asked = question.isEmpty ? "(They asked about a picture, a file, or some text they added.)" : clipped(question, to: questionLimit)
        return "Their question:\n\(asked)\n\nThe answer:\n\(clipped(request.answer.trimmed, to: answerLimit))"
    }

    private static func clipped(_ text: String, to limit: Int) -> String {
        text.count > limit ? "\(text.prefix(limit))…" : text
    }

    // MARK: Drawn from the answer

    /// Suggestions drawn from the answer's shape: its code, then a comparison of the first two things it lists
    /// when the question asked for a choice, then its first term in bold, then what fits any answer to that kind
    /// of question. A short answer without any of those gets asked to go on. English only.
    static func drawn(for request: Request) -> [String] {
        guard request.language == .english else { return [] }
        let blocks = MarkdownBlock.blocks(in: request.answer)
        guard isEnglish(prose(of: blocks)) else { return [] }
        let kind = Kind(of: request.question)
        var suggestions: [String] = []
        if !MarkdownBlock.codeBlocks(in: request.answer).isEmpty {
            suggestions += ["Walk me through this code", "How would I test this?"]
        }
        var compared: [String] = []
        let leads = leadTerms(in: blocks).filter { isTerm($0, after: request.question) }
        if kind == .choice, leads.count >= 2 {
            compared = Array(leads.prefix(2))
            suggestions.append("How do \(compared[0]) and \(compared[1]) compare?")
        }
        let term = terms(in: blocks).first { term in
            isTerm(term.name, after: request.question) && !compared.contains(term.name)
        }
        if let term {
            suggestions.append("Tell me more about \(term.shown)")
        }
        let isShort = request.answer.split(whereSeparator: \.isWhitespace).count < 30
        suggestions += isShort && suggestions.isEmpty ? ["Tell me more", "Why is that?"] : kind.suggestions
        return cleaned(suggestions, for: request)
    }

    /// What kind of question an answer answered, for the suggestions that fit any answer to it.
    enum Kind: Equatable {
        case howTo, task, choice, why, explain, translation, other

        init(of question: String) {
            let text = question.trimmed.lowercased()
            let words = text.split { !$0.isLetter && $0 != "'" }.map(String.init)
            guard let first = words.first else {
                self = .other
                return
            }
            func starts(_ phrases: [String]) -> Bool {
                phrases.contains { text == $0 || text.hasPrefix("\($0) ") }
            }
            if words.contains(where: { $0.hasPrefix("translat") }) {
                self = .translation
            } else if first == "why" {
                self = .why
            } else if starts(["how do i", "how do you", "how do we", "how to", "how can", "how should", "how would", "how might"]) {
                self = .howTo
            } else if first == "which" || starts(["should i", "should we"]) || words.contains(where: Self.choiceWords.contains) {
                self = .choice
            } else if Self.taskWords.contains(first) {
                self = .task
            } else if text.hasSuffix("?") || Self.questionWords.contains(first) {
                self = .explain
            } else {
                self = .other
            }
        }

        private static let choiceWords: Set = ["best", "recommend", "vs", "versus", "compare", "better", "alternatives", "options"]
        private static let taskWords: Set = [
            "make", "write", "create", "build", "fix", "add", "generate", "draft", "implement", "refactor", "rename",
            "convert", "set", "install", "update", "delete", "remove", "clean", "run", "move", "organize", "find",
        ]
        private static let questionWords: Set = [
            "what", "what's", "who", "who's", "when", "where", "how", "is", "are", "does", "do", "can", "explain",
            "define", "tell", "describe",
        ]

        /// Suggestions that fit any answer to this kind of question.
        var suggestions: [String] {
            switch self {
            case .howTo: ["What are common mistakes to avoid?", "Is there a simpler way?"]
            case .task: ["How can I check it worked?", "What could go wrong?"]
            case .choice: ["Which would you pick, and why?", "What are the downsides?"]
            case .why: ["Can you give me an example?", "What are the exceptions?"]
            case .explain: ["Can you give me an example?", "Why does it matter?"]
            case .translation: ["How do I pronounce it?", "How would I say it more casually?"]
            case .other: ["Can you give me an example?", "What should I watch out for?"]
            }
        }
    }

    /// A term an answer sets in bold, and how a suggestion names it: with "the" when the answer puts an article
    /// or a possessive before it ("asks a **resolver**"), as it is otherwise.
    struct Term: Equatable {
        let name: String
        let hasArticle: Bool

        var shown: String { hasArticle ? "the \(name)" : name }
    }

    /// Every term in bold outside code, in order, each once.
    static func terms(in blocks: [MarkdownBlock]) -> [Term] {
        var terms: [Term] = []
        for text in texts(of: blocks) {
            for match in text.matches(of: boldSpan) {
                let name = cleanedTerm(String(match.output.1 ?? match.output.2 ?? ""))
                guard !name.isEmpty, !terms.contains(where: { $0.name.lowercased() == name.lowercased() }) else { continue }
                let before = text[..<match.range.lowerBound].split { !$0.isLetter }.last?.lowercased()
                terms.append(Term(name: name, hasArticle: before.map(articles.contains) ?? false))
            }
        }
        return terms
    }

    /// The terms in bold that start list items, as in "**Obsidian** — local Markdown files", in order.
    static func leadTerms(in blocks: [MarkdownBlock]) -> [String] {
        var leads: [String] = []
        func collect(_ blocks: [MarkdownBlock]) {
            for block in blocks {
                switch block {
                case .list(let items):
                    for item in items where item.depth == 0 {
                        guard let match = item.text.prefixMatch(of: boldSpan) else { continue }
                        let name = cleanedTerm(String(match.output.1 ?? match.output.2 ?? ""))
                        if !name.isEmpty && !leads.contains(name) { leads.append(name) }
                    }
                case .quote(let inner):
                    collect(inner)
                default:
                    break
                }
            }
        }
        collect(blocks)
        return leads
    }

    /// Whether a term is worth a suggestion of its own: a few words that name something, not a label such as
    /// "Note" or "Step 2", and not already in the question.
    static func isTerm(_ term: String, after question: String) -> Bool {
        let words = term.split(separator: " ")
        guard (1...4).contains(words.count), term.count <= 40, term.contains(where: \.isLetter) else { return false }
        guard !term.contains(where: { "?!;".contains($0) }) else { return false }
        let lowered = term.lowercased()
        guard !labels.contains(lowered), lowered.wholeMatch(of: numberedLabel) == nil else { return false }
        return !question.lowercased().contains(lowered)
    }

    /// `**term**` or `__term__`.
    private static var boldSpan: Regex<(Substring, Substring?, Substring?)> { /\*\*([^*\n]+?)\*\*|__([^_\n]+?)__/ }
    /// "Step 2", "Option 3", "Tip #1".
    private static var numberedLabel: Regex<(Substring, Substring)> { /(step|option|tip|part|phase|method|approach|way|idea|example|note)\s*#?\d+/ }
    private static let articles: Set = ["a", "an", "the", "your", "its", "their", "his", "her", "our", "my", "this", "that"]
    /// Words an answer sets in bold to label a part of itself rather than to name anything.
    private static let labels: Set = [
        "note", "notes", "example", "examples", "summary", "tip", "tips", "warning", "important", "caveat", "caveats",
        "pros", "cons", "pro", "con", "conclusion", "tl;dr", "tldr", "answer", "short answer", "long answer", "yes",
        "no", "why", "how", "what", "bottom line", "key takeaways", "takeaway", "takeaways", "update", "edit",
        "result", "results", "output", "input", "usage", "overview", "background", "alternative", "alternatives",
        "recommendation", "verdict", "best for", "good for", "in short", "in summary", "not", "never", "always",
        "must", "do", "don't", "avoid", "before", "after", "option", "step", "steps", "solution", "problem", "fix",
        "reason", "reasons", "benefits", "drawbacks", "downsides", "example usage", "explanation", "how it works",
    ]

    /// A term without the colon or full stop an answer often bolds with it, or the code marks around it.
    private static func cleanedTerm(_ term: String) -> String {
        term.replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":.,—–-"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// The text of the answer's paragraphs, headings, and list items, quotes included, never its code or tables.
    private static func texts(of blocks: [MarkdownBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .paragraph(let text): [text]
            case .heading(_, let text): [text]
            case .list(let items): items.map(\.text)
            case .quote(let inner): texts(of: inner)
            case .code, .table, .rule: []
            }
        }
    }

    private static func prose(of blocks: [MarkdownBlock]) -> String {
        texts(of: blocks).joined(separator: "\n")
    }

    /// Whether the text reads as English, or is too short or mixed to tell.
    static func isEnglish(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(1_000)))
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first else { return true }
        return language == .english || probability < 0.5
    }

    // MARK: Cleaning

    /// The suggestions worth showing, at most `limit`: each on one line, without the quotes, bullets, or numbers a
    /// model puts around it, starting with a capital, never twice, and never a question the chat has asked. Fewer
    /// than `minimum` are none.
    static func cleaned(_ suggestions: [String], for request: Request) -> [String] {
        var seen = Set((request.asked + [request.question]).map(key))
        var kept: [String] = []
        for suggestion in suggestions {
            var text = suggestion.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text = text.replacing(/^(\d+[.)]|[-•*·])\s+/, with: "")
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”„'‘’`").union(.whitespaces))
            guard !text.isEmpty, text.count <= 90 else { continue }
            let firstWord = text.prefix { !$0.isWhitespace }
            if !firstWord.dropFirst().contains(where: \.isUppercase) {
                text = text.prefix(1).uppercased() + text.dropFirst()
            }
            let key = key(text)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            kept.append(text)
            if kept.count == limit { break }
        }
        return kept.count >= minimum ? kept : []
    }

    /// A question as compared with another: its letters and digits, lowercased.
    private static func key(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

extension ChatSession {
    /// A follow-up under the last answer: a click puts it in the input, to change before asking, and a Shift-click
    /// asks it at once, with whatever else the draft holds.
    func followUp(_ question: String, sending: Bool) {
        guard !isStreaming, !isPlaying else { return }
        draft = question
        Log.chat.info("Follow-up \(sending ? "asked" : "put in the input")")
        if sending { send() }
    }
}
