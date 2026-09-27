import Foundation

/// Why an agent wants the tool it asks leave for, in one line, for the Why? button on its ask.
///
/// Only Claude Code stops and waits for an answer, so Claude Code explains, in a short run of its own beside
/// the one that is waiting: its small model, no thinking, no tools, no MCP servers, nothing kept. The chat goes
/// nowhere it wasn't going already, and the reason is kept only by the card that asked for it.
nonisolated enum ToolReason {
    /// Claude's small model, whatever the model set for answers: the reason is one line, wanted in seconds.
    static let model = "haiku"
    /// How many of the chat's last turns the model reads, the one being answered included.
    static let turnLimit = 3
    /// How much of a question, an answer, or the tool's input it reads, in characters.
    static let textLimit = 1_500
    static let inputLimit = 3_000

    /// The instructions until Settings › Prompt changes them.
    static let systemPrompt = """
    You explain why an AI agent wants to use a tool, so the person it works for can decide whether to allow it. \
    Reply with one plain sentence of at most 25 words: what the call would do and how it serves what the person asked. \
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
        guard let executable = CommandLineClient.resolve(settings.baseURL) else {
            throw LLMError.commandNotFound(.claudeCode, settings.baseURL.trimmed)
        }
        Log.commandLine.info("Asking Claude Code why it asks \(prompt.kind.logDescription)")
        let output = try await CommandLineClient.output(
            of: executable,
            arguments: arguments(instructions: instructions),
            input: Data(question(for: prompt, in: turns).utf8),
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
        var parts = ["<conversation>\n\(conversation.joined(separator: "\n\n"))\n</conversation>"]
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
