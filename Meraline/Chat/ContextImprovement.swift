import Foundation

/// Improve on the Context card, in Decision mode while Live is on (see `ChatSession.improveContext()`): the LLM
/// edits the text on the card toward the answers the live decisions should give. It reads the text, the other
/// texts the decisions read with it, each question on with the answers it picks from and the answer it has now,
/// and the answer each should get (`goal(of:answered:)`), and edits a little, never rewrites, so a click or two
/// more takes a draft that is 65% flirt further; it adds a sentence at the end only once nothing in the text can
/// be improved. The reply is the text and nothing else (`text(from:improving:)`), and it goes nowhere but back to
/// the card.
nonisolated enum ContextImprovement {
    /// The instructions until Settings › Prompt changes them.
    static let systemPrompt = """
    You improve a text someone is writing, so that a model deciding about it answers the way they want. \
    You get the text, each question the model is asked about it with the answers it picks from, \
    how it answered just now with its probabilities, and the answer the text should get. \
    Edit, don't rewrite: keep the person's words, voice, meaning, length, language, and formatting, \
    and make small or medium changes only where they move an answer toward what it should be, \
    a word, a phrase, or a sentence at a time. Never replace the text whole. \
    Add nothing while something in the text can still be improved; only then add one sentence at its end, and nothing more. \
    Reply with only the edited text: no preamble, no comment on what changed, no quotes, and no Markdown around it.
    """

    /// How much of each other text the model reads, in characters. The text it improves goes whole, since its
    /// reply takes that text's place.
    static let otherTextLimit = 4_000

    /// What the model wrote, and what the request took, for the ledger.
    struct Reply: Equatable, Sendable {
        let text: String
        let usage: TokenUsage?
    }

    /// The answer a question's text should get: Yes on a yes-or-no question, the last of levels in order, and from
    /// a list of answers the one the text has now, or the first before an answer came, since among those there is
    /// no best one to pick.
    static func goal(of question: LiveQuestion, answered answer: Decision?) -> String {
        let options = question.answers.options
        switch question.answers.kind {
        case .yesNo:
            return options.first { $0.lowercased() == "yes" } ?? "Yes"
        case .score:
            return options.last ?? ""
        case .choice:
            return answer?.chosen.label ?? options.first ?? ""
        }
    }

    /// What the model reads: the text, the other texts the decisions read with it, which stay as they are, and
    /// each question on, with its answers, how it was answered, and what it should be answered.
    static func question(text: String, others: [SelectedText], questions: [LiveQuestion], answers: [LiveQuestion.ID: Decision]) -> String {
        var parts = ["The text to improve:\n<text>\n\(text.trimmed)\n</text>"]
        if !others.isEmpty {
            let fixed = others.map { other in
                "<text from=\"\(other.sourceLabel)\">\n\(clipped(other.text, to: otherTextLimit))\n</text>"
            }
            parts.append("The decisions also read \(others.count == 1 ? "this text" : "these texts"), which you cannot change:\n\(fixed.joined(separator: "\n"))")
        }
        let asked = questions.enumerated().map { offset, question in
            var lines = ["\(offset + 1). \(question.question)"]
            if question.title != question.question { lines[0] += " (\(question.title))" }
            let options = question.answers.options
            lines.append(question.answers.kind == .score
                ? "   Answers, in order: \(options.joined(separator: " < "))"
                : "   Answers: \(options.joined(separator: " / "))")
            if let answer = answers[question.id] {
                let shares = answer.options.map { "\($0.label) \(Decision.percent($0.probability))" }.joined(separator: ", ")
                lines.append("   Now: \(shares) (\(Decision.percent(answer.confidence)) confident)")
            } else {
                lines.append("   Now: not decided yet")
            }
            lines.append("   Should be: \(goal(of: question, answered: answers[question.id]))")
            return lines.joined(separator: "\n")
        }
        parts.append("The questions, with the model's answers now and what each should be:\n\(asked.joined(separator: "\n"))")
        parts.append("Edit the text so that each question's answer becomes what it should be, as surely as possible, with the fewest changes that do it. Reply with the edited text only.")
        return parts.joined(separator: "\n\n")
    }

    /// Asks `provider` to improve `text`, in a request of its own with its settings less the web and MCP servers,
    /// and no workspace: an agent gets a folder for this run alone, and an ask it makes on the way is turned down.
    /// `stream` talks to the provider; tests pass one that replies on its own.
    @MainActor
    static func improve(
        _ text: String,
        beside others: [SelectedText],
        toward questions: [LiveQuestion],
        answered answers: [LiveQuestion.ID: Decision],
        provider: Provider,
        settings: ProviderSettings,
        instructions: String = systemPrompt,
        stream: @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> = LLMClient.stream
    ) async throws -> Reply {
        var settings = settings
        settings.allowsWebSearch = false
        settings.allowsMCP = false
        let asked = question(text: text, others: others, questions: questions, answers: answers)
        let request = ChatRequest(provider: provider, settings: settings, systemPrompt: instructions, messages: [ChatMessage(role: .user, text: asked)])
        // As in the chat, words that come after a tool take the place of the ones before it.
        var reply = ""
        var startsOver = false
        var usage: TokenUsage?
        for try await output in stream(request) {
            switch output {
            case .text(let part):
                reply = startsOver ? part : reply + part
                startsOver = false
            case .activity:
                startsOver = !reply.isEmpty
            case .usage(let took, let adds):
                usage = (usage ?? .zero).merging(took, adding: adds)
            case .prompt(_, let responder?):
                responder(.deny)
            case .prompt, .presented, .decision, .decisions, .presetDecisions:
                break
            }
        }
        let improved = Self.text(from: reply, improving: text)
        guard !improved.isEmpty else { throw LLMError.emptyResponse }
        return Reply(text: improved, usage: usage)
    }

    /// The reply as the text: its ends trimmed, and a code fence or a pair of quotes the model put around it taken
    /// off, unless `original` began that way itself, in which case they are the text's own.
    static func text(from reply: String, improving original: String) -> String {
        var text = reply.trimmed
        let original = original.trimmed
        if text.hasPrefix("```"), text.hasSuffix("```"), !original.hasPrefix("```") {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            lines.removeFirst()
            if lines.last?.trimmed == "```" { lines.removeLast() } else if let last = lines.last {
                lines[lines.count - 1] = last.dropLast(3)
            }
            text = lines.joined(separator: "\n").trimmed
        }
        for (opening, closing) in [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")] where text.count > 2 {
            if text.hasPrefix(opening), text.hasSuffix(closing), !original.hasPrefix(opening) {
                text = String(text.dropFirst().dropLast()).trimmed
            }
        }
        return text
    }

    /// `text` cut to `limit` characters, keeping its start.
    private static func clipped(_ text: String, to limit: Int) -> String {
        let text = text.trimmed
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
