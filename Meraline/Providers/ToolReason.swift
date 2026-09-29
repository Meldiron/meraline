import Foundation

/// Why an agent wants the tool it asks leave for, or why it used one of the tools under a finished answer, in one
/// line: the Why? button on its ask, and a click on a tool's capsule.
///
/// Only Claude Code stops and waits for an answer, so Claude Code explains its asks, in a short run of its own
/// beside the one that is waiting: its small model, no thinking, no tools, no MCP servers, nothing kept. A tool
/// under an answer is explained by the provider that answered, the same short run for Claude Code and a request
/// of its own for any other (see `explain(toolAt:of:in:provider:settings:instructions:stream:)`). The chat goes
/// nowhere it wasn't going already, and the reason is kept only by the view that asked for it.
nonisolated enum ToolReason {
    /// Claude's small model, whatever the model set for answers: the reason is one line, wanted in seconds.
    static let model = "haiku"
    /// How many of the chat's last turns the model reads, the one being answered, or asked about, included.
    static let turnLimit = 3
    /// How much of a question, an answer, or the tool's input it reads, in characters.
    static let textLimit = 1_500
    static let inputLimit = 3_000

    /// The instructions until Settings › Prompt changes them.
    static let systemPrompt = """
    You explain why an AI agent wants to use a tool, or why it used one, so the person it works for can decide \
    whether to allow it or see what it was for. \
    Reply with one plain sentence of at most 25 words: what the call does and how it serves what the person asked. \
    If it goes beyond what they asked, or looks risky, say so. No preamble, no quotes, no Markdown.
    """

    static func arguments(instructions: String) -> [String] {
        [
            "--print",
            "--model", model,
            "--tools", "",
            "--strict-mcp-config",
            "--no-session-persistence",
            "--system-prompt", instructions
        ]
    }

    /// A thinking pass would triple the wait for one sentence.
    static let environment = ["MAX_THINKING_TOKENS": "0"]

    /// Asks Claude Code why it wants what `prompt` asks for, reading the chat's last turns. `settings` are
    /// Claude Code's own, for the command to run, and `instructions` the prompt Settings › Prompt has for Why?.
    static func explain(
        _ prompt: AgentPrompt,
        in turns: [ChatSession.Turn],
        settings: ProviderSettings,
        instructions: String = systemPrompt
    ) async throws -> String {
        Log.commandLine.info("Asking Claude Code why it asks \(prompt.kind.logDescription)")
        return try await askClaudeCode(question(for: prompt, in: turns), settings: settings, instructions: instructions)
    }

    /// Asks the provider that answered `turn` why it used the tool at `index` of the answer's trail, reading the
    /// chat up to that answer. Claude Code says in its short run; any other provider in a request of its own with
    /// the settings it answers with, less the web and MCP servers, and no workspace: an agent gets a folder for
    /// that run alone. An ask it makes on the way is turned down. `stream` talks to the provider; tests pass one
    /// that replies on its own.
    static func explain(
        toolAt index: Int,
        of turn: ChatSession.Turn,
        in turns: [ChatSession.Turn],
        provider: Provider,
        settings: ProviderSettings,
        instructions: String = systemPrompt,
        stream: @Sendable (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> = LLMClient.stream
    ) async throws -> String {
        let question = question(forToolAt: index, of: turn, in: turns, agent: provider.name)
        Log.providers.info("Asking \(provider.name) why it used a tool")
        if provider == .claudeCode {
            return try await askClaudeCode(question, settings: settings, instructions: instructions)
        }
        var settings = settings
        settings.allowsWebSearch = false
        settings.allowsMCP = false
        let request = ChatRequest(provider: provider, settings: settings, systemPrompt: instructions, messages: [ChatMessage(role: .user, text: question)])
        // As in the chat, words that come after a tool take the place of the ones before it.
        var reply = ""
        var startsOver = false
        for try await output in stream(request) {
            switch output {
            case .text(let text):
                reply = startsOver ? text : reply + text
                startsOver = false
            case .activity:
                startsOver = !reply.isEmpty
            case .prompt(_, let responder?):
                responder(.deny)
            case .prompt, .presented, .usage, .decision, .decisions:
                break
            }
        }
        guard let reason = firstLine(of: reply) else { throw LLMError.emptyResponse }
        return reason
    }

    /// The first line of Claude Code's short run, reading `question` on stdin.
    private static func askClaudeCode(_ question: String, settings: ProviderSettings, instructions: String) async throws -> String {
        guard let executable = CommandLineClient.resolve(settings.baseURL) else {
            throw LLMError.commandNotFound(.claudeCode, settings.baseURL.trimmed)
        }
        let output = try await CommandLineClient.output(
            of: executable,
            arguments: arguments(instructions: instructions),
            input: Data(question.utf8),
            extraEnvironment: environment,
            timeout: .seconds(60)
        )
        guard let reason = firstLine(of: output) else { throw LLMError.emptyResponse }
        return reason
    }

    /// What the model reads: the chat's last turns, what the agent has said so far in the one it is answering,
    /// and the call it asks leave for, each cut short when long.
    static func question(for prompt: AgentPrompt, in turns: [ChatSession.Turn], agent: String = Provider.claudeCode.name) -> String {
        let recent = Array(turns.suffix(turnLimit))
        var parts = [conversation(of: recent, agent: agent)]
        if let answer = recent.last?.answer.trimmed, !answer.isEmpty {
            parts.append("\(agent) has said so far:\n<answer>\n\(clipped(answer, to: textLimit, keepingEnd: true))\n</answer>")
        }
        let input = clipped(String(decoding: prompt.input, as: UTF8.self), to: inputLimit)
        switch prompt.kind {
        case .permission(let activity, _):
            parts.append("\(agent) now asks to \(activity.request), with this input:\n<tool_input>\n\(input)\n</tool_input>")
        case .question:
            parts.append("\(agent) now asks the person a question:\n<tool_input>\n\(input)\n</tool_input>")
        }
        parts.append("Why does it want this?")
        return parts.joined(separator: "\n\n")
    }

    /// What the model reads for a tool under a finished answer: the chat's last turns up to that answer, the
    /// answer, and the tools it used in order, with the one asked about named. The trail keeps no tool's input,
    /// so the model reads what the capsules say: a search's words, a page's address, a tool's name.
    static func question(forToolAt index: Int, of turn: ChatSession.Turn, in turns: [ChatSession.Turn], agent: String) -> String {
        let upToTurn = turns.firstIndex { $0.id == turn.id }.map { Array(turns[...$0]) } ?? [turn]
        var parts = [conversation(of: Array(upToTurn.suffix(turnLimit)), agent: agent)]
        if !turn.answer.trimmed.isEmpty {
            parts.append("\(agent) answered:\n<answer>\n\(clipped(turn.answer, to: textLimit))\n</answer>")
        }
        let tools = turn.tools.enumerated().map { "\($0.offset + 1). \($0.element.title)" }
        parts.append("While answering, \(agent) used \(tools.count == 1 ? "this tool" : "these tools, in order"):\n\(tools.joined(separator: "\n"))")
        parts.append("Why did it \(turn.tools[index].request)\(tools.count == 1 ? "" : " (tool \(index + 1))")?")
        return parts.joined(separator: "\n\n")
    }

    /// The chat's last turns as the model reads them: each question with what came with it, and each answer but
    /// the last one's, which the question shows on its own.
    private static func conversation(of recent: [ChatSession.Turn], agent: String) -> String {
        var conversation: [String] = []
        for (index, turn) in recent.enumerated() {
            var asked = clipped(turn.cue ?? turn.question, to: textLimit)
            let attached = turn.files.map { $0.name + ($0.isFolder ? "/" : "") }
            if !attached.isEmpty { asked += " (attached: \(attached.joined(separator: ", ")))" }
            if !turn.selections.isEmpty { asked += " (about \(turn.selections.count == 1 ? "a text" : "\(turn.selections.count) texts") they selected)" }
            conversation.append("Person: \(asked)")
            if index < recent.count - 1, !turn.answer.isEmpty {
                conversation.append("\(agent): \(clipped(turn.answer, to: textLimit, keepingEnd: true))")
            }
        }
        return "<conversation>\n\(conversation.joined(separator: "\n\n"))\n</conversation>"
    }

    /// The reply's first line with text, without quotes around it.
    static func firstLine(of output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"“”"))) }
            .first { !$0.isEmpty }
    }

    /// `text` cut to `limit` characters, keeping its start, or its end when that is where the news is.
    private static func clipped(_ text: String, to limit: Int, keepingEnd: Bool = false) -> String {
        let text = text.trimmed
        guard text.count > limit else { return text }
        return keepingEnd ? "…" + String(text.suffix(limit)) : String(text.prefix(limit)) + "…"
    }
}
