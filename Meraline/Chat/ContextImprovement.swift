import Foundation

/// Improve on the Context card, in Decision mode while Live is on (see `ChatSession.improveContext()`): the LLM
/// changes the text on the card toward the answers the live decisions should give. It reads the text, the other
/// texts the decisions read with it, each question on with the answers it picks from and the answer it has now,
/// and the answer each should get (`goal(of:answered:)`), and changes as much as its stage allows (`Stage`): a
/// click starts with small edits, which keep the person's words, and asks for more in the same click while the
/// text comes back as it was, parts of it rewritten, then the whole; and once the live decisions show that what
/// a stage could do didn't make the answers surer, the next click starts a stage deeper (`nextStage`), so a text
/// that no small edit can carry past 65% is rewritten rather than left with a note that nothing can be done. The
/// reply is the text and nothing else (`text(from:improving:)`), and it goes nowhere but back to the card.
nonisolated enum ContextImprovement {
    /// How much a request may change the text, from the least to the most. The one Improve prompt (Settings ›
    /// Prompt › Decisions) serves every stage: the stage's `instruction` goes with each request, after the
    /// questions.
    enum Stage: Int, CaseIterable, Sendable {
        /// Small changes where they move an answer: a word, a phrase, or a sentence at a time, and a sentence
        /// added at the end only once nothing else can be improved.
        case edit
        /// The sentences and paragraphs in the answers' way rewritten, reordered, added, or dropped, the rest left
        /// as it is.
        case parts
        /// The text written anew, keeping only what it is about and whom it speaks to.
        case whole

        /// The stage after this one, or nil past the whole text.
        var next: Stage? { Stage(rawValue: rawValue + 1) }

        /// What the model may change, told after the questions.
        var instruction: String {
            switch self {
            case .edit:
                "Edit, don't rewrite: keep the person's words, voice, meaning, length, and formatting, " +
                "and make small changes only where they move an answer toward what it should be, a word, a phrase, or a sentence at a time. " +
                "Never replace the text whole. Add nothing while something in the text can still be improved; only then add one sentence at its end, and nothing more."
            case .parts:
                "Small edits were not enough. Rewrite the sentences and paragraphs that stand in the answers' way, " +
                "and reorder, add, or drop sentences where that helps; leave the rest as it is. " +
                "Keep the person's meaning, voice, and formatting, and about the length."
            case .whole:
                "Edits and rewritten parts were not enough. Write the text anew so that it gets the answers it should, as surely as you can: " +
                "keep what it is about and whom it speaks to, and change its words, structure, tone, and length as much as that takes."
            }
        }

        /// The note's first words once the stage landed: what was done to the text.
        var done: String {
            switch self {
            case .edit: "Improved"
            case .parts: "Rewrote parts"
            case .whole: "Rewrote the text"
            }
        }

        /// What the next click does, for the button's help.
        var promise: String {
            switch self {
            case .edit: "edits the text a little"
            case .parts: "rewrites the parts of the text in the answers' way"
            case .whole: "rewrites the text whole"
            }
        }
    }

    /// The instructions until Settings › Prompt changes them.
    static let systemPrompt = """
    You improve a text someone is writing, so that a model deciding about it answers the way they want. \
    You get the text, each question the model is asked about it with the answers it picks from, \
    how it answered just now with its probabilities, the answer the text should get, \
    and how much you may change: small edits, parts rewritten, or the whole text. \
    Change no more than that allows, and keep the person's language. \
    Reply with only the edited text: no preamble, no comment on what changed, no quotes, and no Markdown around it.
    """

    /// How much of each other text the model reads, in characters. The text it improves goes whole, since its
    /// reply takes that text's place.
    static let otherTextLimit = 4_000

    /// The confidence the answers are improved toward, as the capsules show it: at or above it a question's
    /// answer is what it should be, and a click only polishes (see `nextStage`).
    static let sureEnough = 0.9
    /// The least the goals' shares have to rise, on average, for an improvement to count as helping; under it the
    /// next click starts a stage deeper (see `nextStage`), since a decision's numbers wobble by a point or two on
    /// their own.
    static let leastGain = 0.02

    /// What the model wrote, how much it was allowed to change (the stage its reply came from, or the last one
    /// asked when every reply gave the text back as it was), how many requests the click took, and what they took
    /// together, for the ledger.
    struct Reply: Equatable, Sendable {
        let text: String
        let stage: Stage
        let requests: Int
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

    /// The share a decision gives `goal`, from 0 to 1, or 0 for an answer it doesn't list.
    static func share(of goal: String, in decision: Decision) -> Double {
        decision.options.first { $0.label.caseInsensitiveCompare(goal) == .orderedSame }?.probability ?? 0
    }

    /// Whether a decision is what it should be: `goal` chosen, `sureEnough` or more.
    static func isReached(_ decision: Decision, goal: String) -> Bool {
        decision.chosen.label.caseInsensitiveCompare(goal) == .orderedSame && decision.confidence >= sureEnough
    }

    /// The stage the next click starts at, after the last improvement landed at `stage`, asked with the answers
    /// `before` and decided about since as `after` (the answers that have come about its text; `questions` are
    /// those on): `.edit` once every question's answer is what it should be, since a click then only polishes;
    /// else the same stage while the goals' shares rose by `leastGain` on average, which is working; else the next
    /// stage, since what this one could do didn't help, and `.whole` stays itself. With nothing decided yet about
    /// the improved text, the same stage.
    static func nextStage(after stage: Stage, questions: [LiveQuestion], before: [LiveQuestion.ID: Decision], after: [LiveQuestion.ID: Decision]) -> Stage {
        var gains: [Double] = []
        var reached = !questions.isEmpty
        for question in questions {
            let goal = goal(of: question, answered: before[question.id])
            guard let now = after[question.id] else {
                reached = false
                continue
            }
            if !isReached(now, goal: goal) { reached = false }
            if let then = before[question.id] { gains.append(share(of: goal, in: now) - share(of: goal, in: then)) }
        }
        if reached { return .edit }
        guard !gains.isEmpty else { return stage }
        let gain = gains.reduce(0, +) / Double(gains.count)
        return gain >= leastGain ? stage : (stage.next ?? stage)
    }

    /// What the model reads: the text, the other texts the decisions read with it, which stay as they are, each
    /// question on, with its answers, how it was answered, and what it should be answered, and how much the stage
    /// lets it change.
    static func question(text: String, others: [SelectedText], questions: [LiveQuestion], answers: [LiveQuestion.ID: Decision], stage: Stage = .edit) -> String {
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
        parts.append("Change the text so that each question's answer becomes what it should be, \(Decision.percent(sureEnough)) confident or more. \(stage.instruction) Reply with the edited text only.")
        return parts.joined(separator: "\n\n")
    }

    /// Asks `provider` to improve `text`, in a request of its own with its settings less the web and MCP servers,
    /// and no workspace: an agent gets a folder for this run alone, and an ask it makes on the way is turned down.
    /// It starts at `stage` and, while the text comes back as it was, asks the next stage in the same click, up
    /// to the whole text; the reply says which stage its text came from, and the text comes back as it was only
    /// once even a whole rewrite gave it back so. `stream` talks to the provider; tests pass one that replies on
    /// its own.
    @MainActor
    static func improve(
        _ text: String,
        beside others: [SelectedText],
        toward questions: [LiveQuestion],
        answered answers: [LiveQuestion.ID: Decision],
        from stage: Stage = .edit,
        provider: Provider,
        settings: ProviderSettings,
        instructions: String = systemPrompt,
        stream: @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> = LLMClient.stream
    ) async throws -> Reply {
        var settings = settings
        settings.allowsWebSearch = false
        settings.allowsMCP = false
        var stage = stage
        var requests = 0
        var usage: TokenUsage?
        while true {
            let asked = question(text: text, others: others, questions: questions, answers: answers, stage: stage)
            let request = ChatRequest(provider: provider, settings: settings, systemPrompt: instructions, messages: [ChatMessage(role: .user, text: asked)])
            requests += 1
            let (reply, took) = try await read(stream(request))
            if let took { usage = usage?.merging(took, adding: true) ?? took }
            let improved = Self.text(from: reply, improving: text)
            guard !improved.isEmpty else { throw LLMError.emptyResponse }
            guard improved == text.trimmed, let next = stage.next else {
                return Reply(text: improved, stage: stage, requests: requests, usage: usage)
            }
            try Task.checkCancellation()
            Log.chat.info("The Context card's text came back as it was from \(stage); asking \(provider.name) for \(next)")
            stage = next
        }
    }

    /// The reply's words and what it took. As in the chat, words that come after a tool take the place of the
    /// ones before it.
    @MainActor
    private static func read(_ stream: AsyncThrowingStream<StreamOutput, Error>) async throws -> (text: String, usage: TokenUsage?) {
        var reply = ""
        var startsOver = false
        var usage: TokenUsage?
        for try await output in stream {
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
        return (reply, usage)
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
