import Foundation

nonisolated enum StreamChunk: Equatable, Sendable {
    case text(String)
    case activity(Activity)
    /// The agent stopped to ask, or reports that it turned an ask of its own down.
    case prompt(AgentPrompt)
    case finished
    case ignored
}

nonisolated enum StreamOutput: Equatable, Sendable {
    case text(String)
    case activity(Activity)
    /// The responder carries the answer back; a prompt the agent settled itself has none.
    case prompt(AgentPrompt, AgentPromptResponder?)
}

nonisolated enum Activity: Equatable, Sendable {
    case thinking
    case searching(String?)
    case reading(String?)
    case running
    case tool(String)
    /// A tool from one of the MCP servers set up in an agent, by server and tool name.
    case mcp(server: String, tool: String)
    /// Meraline copying an attached folder into the workspace before the agent starts. Not a tool.
    case copying(String)

    /// `knownServers` are the MCP servers the agent listed, so a tool can be shown under its server's
    /// name: Claude Code spells servers into tool names as `mcp__<server>__<tool>` and OpenCode as
    /// `<server>_<tool>`.
    static func named(_ name: String, query: String? = nil, url: String? = nil, knownServers: [String] = []) -> Activity {
        if let mcp = mcpTool(named: name, knownServers: knownServers) { return mcp }
        switch name.lowercased() {
        case "websearch", "web_search": return .searching(query)
        case "webfetch", "web_fetch", "fetch": return .reading(url.flatMap { URL(string: $0)?.host() } ?? url)
        case "bash", "shell", "command_execution": return .running
        default: return .tool(name)
        }
    }

    private static func mcpTool(named name: String, knownServers: [String]) -> Activity? {
        if name.hasPrefix("mcp__") {
            let parts = name.dropFirst("mcp__".count).components(separatedBy: "__")
            let prefix = parts[0]
            let server = knownServers.first { MCPServer.toolPrefix(for: $0) == prefix } ?? prefix
            return .mcp(server: server, tool: parts.dropFirst().joined(separator: "__"))
        }
        let server = knownServers
            .filter { name.hasPrefix($0 + "_") && name.count > $0.count + 1 }
            .max { $0.count < $1.count }
        guard let server else { return nil }
        return .mcp(server: server, tool: String(name.dropFirst(server.count + 1)))
    }

    var title: String {
        switch self {
        case .thinking: "Thinking"
        case .searching(let query?): "Searching for “\(query)”"
        case .searching: "Searching the web"
        case .reading(let page?): "Reading \(page)"
        case .reading: "Reading a page"
        case .running: "Running a command"
        case .tool(let name): "Using \(name)"
        case .mcp(let server, let tool): tool.isEmpty ? "Asking \(server)" : "Asking \(server) to \(MCPServer.humanized(tool))"
        case .copying(let folder): "Copying “\(folder)”"
        }
    }

    /// What the agent asks leave for, after "asks to": "use Write", "ask knowledge-rag to search knowledge".
    var request: String {
        switch self {
        case .thinking: "think"
        case .searching(let query?): "search the web for “\(query)”"
        case .searching: "search the web"
        case .reading(let page?): "read \(page)"
        case .reading: "read a page"
        case .running: "run a command"
        case .tool(let name): "use \(name)"
        case .mcp(let server, let tool): tool.isEmpty ? "ask \(server)" : "ask \(server) to \(MCPServer.humanized(tool))"
        case .copying(let folder): "copy \(folder)"
        }
    }

    /// A few words for the trail of tools under an answer.
    var label: String {
        switch self {
        case .thinking: "Thinking"
        case .searching: "Web search"
        case .reading(let page?): page
        case .reading: "Web page"
        case .running: "Command"
        case .tool(let name): name
        case .mcp(let server, let tool): tool.isEmpty ? server : "\(server): \(MCPServer.humanized(tool))"
        case .copying(let folder): folder
        }
    }

    var symbol: String {
        switch self {
        case .thinking: "brain"
        case .searching: "magnifyingglass"
        case .reading: "doc.text"
        case .running: "terminal"
        case .tool: "wrench.and.screwdriver"
        case .mcp: "puzzlepiece.extension"
        case .copying: "folder"
        }
    }

    /// The same kind of step, whatever the details: two searches, two pages, the same MCP tool.
    func isSameStep(as other: Activity) -> Bool {
        switch (self, other) {
        case (.thinking, .thinking), (.searching, .searching), (.reading, .reading), (.running, .running): true
        case (.tool(let mine), .tool(let theirs)): mine == theirs
        case (.mcp(let server, let tool), .mcp(let otherServer, let otherTool)): server == otherServer && tool == otherTool
        default: false
        }
    }

    /// A step announced before its details were known, like a search without its query.
    var isVague: Bool {
        switch self {
        case .searching(nil), .reading(nil): true
        default: false
        }
    }
}

nonisolated enum StreamDecoder {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// `knownServers` are the MCP servers an agent listed, so its tools show under their server's name.
    static func decode(_ payload: String, from provider: Provider, knownServers: [String] = []) throws -> StreamChunk {
        switch provider {
        case .anthropic: try anthropic(payload)
        case .openAI: try openAIResponses(payload)
        case .gemini: try gemini(payload)
        case .openRouter, .custom: try chatCompletions(payload)
        case .ollama: try ollama(payload)
        case .claudeCode: try claudeCode(payload, knownServers: knownServers)
        case .codex: try codex(payload)
        case .opencode: try opencode(payload, knownServers: knownServers)
        case .apple: .ignored
        }
    }

    static func errorMessage(from data: Data) -> String {
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message ?? envelope.message, !message.isEmpty {
            return message
        }
        let text = String(decoding: data.prefix(500), as: UTF8.self).trimmed
        return text.isEmpty ? "The request failed." : text
    }

    private static func anthropic(_ payload: String) throws -> StreamChunk {
        try anthropic(decoder.decode(AnthropicEvent.self, from: Data(payload.utf8)))
    }

    private static func anthropic(_ event: AnthropicEvent, knownServers: [String] = []) throws -> StreamChunk {
        switch event.type {
        case "content_block_start":
            switch event.contentBlock?.type {
            case "thinking", "redacted_thinking": return .activity(.thinking)
            case "tool_use", "server_tool_use": return .activity(.named(event.contentBlock?.name ?? "tool", knownServers: knownServers))
            default: break
            }
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text { return .text(text) }
        case "message_delta":
            switch event.delta?.stopReason {
            case "refusal": throw LLMError.refused
            case "max_tokens": throw LLMError.truncated
            default: break
            }
        case "message_stop":
            return .finished
        case "error":
            throw LLMError.provider(event.error?.message ?? "Anthropic reported an error.")
        default:
            break
        }
        return .ignored
    }

    private static func openAIResponses(_ payload: String) throws -> StreamChunk {
        let data = Data(payload.utf8)
        let kind = try decoder.decode(EventKind.self, from: data).type
        switch kind {
        case "response.output_text.delta":
            return .text(try decoder.decode(ResponsesTextDelta.self, from: data).delta)
        case "response.output_item.added":
            switch try decoder.decode(ResponsesItemAdded.self, from: data).item.type {
            case "reasoning": return .activity(.thinking)
            case "web_search_call": return .activity(.searching(nil))
            default: return .ignored
            }
        case "response.completed":
            return .finished
        case "response.incomplete":
            throw LLMError.truncated
        case "response.failed":
            let failure = try decoder.decode(ResponsesFailure.self, from: data)
            throw LLMError.provider(failure.response.error?.message ?? "OpenAI couldn’t complete the response.")
        case "error":
            let error = try decoder.decode(ErrorDetail.self, from: data)
            throw LLMError.provider(error.message ?? "OpenAI reported an error.")
        default:
            return .ignored
        }
    }

    private static func chatCompletions(_ payload: String) throws -> StreamChunk {
        if payload == "[DONE]" { return .finished }
        let chunk = try decoder.decode(ChatCompletionChunk.self, from: Data(payload.utf8))
        if let message = chunk.error?.message { throw LLMError.provider(message) }
        guard let choice = chunk.choices?.first else { return .ignored }
        if choice.finishReason == "length" { throw LLMError.truncated }
        if let content = choice.delta?.content, !content.isEmpty { return .text(content) }
        return .ignored
    }

    private static func gemini(_ payload: String) throws -> StreamChunk {
        let chunk = try decoder.decode(GeminiChunk.self, from: Data(payload.utf8))
        if let message = chunk.error?.message { throw LLMError.provider(message) }
        if let reason = chunk.promptFeedback?.blockReason {
            throw LLMError.provider("Gemini blocked this request (\(reason)).")
        }
        guard let candidate = chunk.candidates?.first else { return .ignored }
        let parts = candidate.content?.parts ?? []
        let text = parts.compactMap { $0.thought == true ? nil : $0.text }.joined()
        if !text.isEmpty { return .text(text) }
        if parts.contains(where: { $0.thought == true }) { return .activity(.thinking) }
        switch candidate.finishReason {
        case "MAX_TOKENS": throw LLMError.truncated
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII": throw LLMError.refused
        default: return .ignored
        }
    }

    private static func claudeCode(_ payload: String, knownServers: [String]) throws -> StreamChunk {
        guard let line = try? decoder.decode(ClaudeCodeLine.self, from: Data(payload.utf8)) else { return .ignored }
        switch line.type {
        case "stream_event":
            guard let event = line.event else { return .ignored }
            return try anthropic(event, knownServers: knownServers)
        case "assistant":
            guard let tool = line.message?.content?.last(where: { $0.type == "tool_use" }), let name = tool.name else {
                return .ignored
            }
            return .activity(.named(name, query: tool.input?.query, url: tool.input?.url, knownServers: knownServers))
        case "control_request":
            return claudeCodePrompt(payload, knownServers: knownServers)
        case "result":
            if line.isError == true { throw LLMError.provider(line.result ?? "Claude Code couldn’t answer.") }
            return .finished
        default:
            return .ignored
        }
    }

    /// Claude Code stopped to ask: leave to use a tool, or a question of its own (`AskUserQuestion`,
    /// which arrives as a permission request for that tool). The answer goes back on stdin, see
    /// `AgentPrompt.claudeCodeResponse`. The tool's input is kept as sent so it can be echoed back.
    private static func claudeCodePrompt(_ payload: String, knownServers: [String]) -> StreamChunk {
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let id = object["request_id"] as? String,
              let request = object["request"] as? [String: Any],
              request["subtype"] as? String == "can_use_tool",
              let tool = request["tool_name"] as? String else { return .ignored }
        let input = request["input"] as? [String: Any] ?? [:]
        let encoded = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])) ?? Data()
        if tool == "AskUserQuestion" {
            let questions = (input["questions"] as? [[String: Any]] ?? []).compactMap { question -> AgentPrompt.Question? in
                guard let text = question["question"] as? String, !text.isEmpty else { return nil }
                let options = (question["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentPrompt.Question.Option? in
                    guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                    return AgentPrompt.Question.Option(label: label, detail: option["description"] as? String)
                }
                return AgentPrompt.Question(
                    header: question["header"] as? String ?? "",
                    text: text,
                    options: options,
                    multiSelect: question["multiSelect"] as? Bool ?? false
                )
            }
            if !questions.isEmpty { return .prompt(AgentPrompt(id: id, kind: .question(questions), input: encoded)) }
        }
        let activity = Activity.named(tool, query: input["query"] as? String, url: input["url"] as? String, knownServers: knownServers)
        // A command's description is claude's own summary of it, so the prompt shows the command itself.
        let detail = (input["command"] ?? input["skill"]) as? String ?? request["description"] as? String ?? detail(of: input)
        return .prompt(AgentPrompt(id: id, kind: .permission(activity, detail: detail), input: encoded))
    }

    /// What a tool would act on, for the prompt: the file, the command, the address, the query.
    private static func detail(of input: [String: Any]) -> String? {
        if let path = input["file_path"] as? String { return URL(fileURLWithPath: path).lastPathComponent }
        if let command = input["command"] as? String { return command }
        if let url = input["url"] as? String { return url }
        if let query = input["query"] as? String { return query }
        return nil
    }

    private static func codex(_ payload: String) throws -> StreamChunk {
        guard let line = try? decoder.decode(CodexLine.self, from: Data(payload.utf8)) else { return .ignored }
        switch line.type {
        case "item.started":
            switch line.item?.type {
            case "reasoning": return .activity(.thinking)
            case "command_execution": return .activity(.running)
            case "web_search": return .activity(.searching(line.item?.query))
            case "mcp_tool_call": return .activity(.mcp(server: line.item?.server ?? "an MCP server", tool: line.item?.tool ?? ""))
            default: return .ignored
            }
        case "item.completed":
            guard line.item?.type == "agent_message", let text = line.item?.text, !text.isEmpty else { return .ignored }
            return .text(text)
        case "turn.completed":
            return .finished
        case "turn.failed":
            throw LLMError.provider(unwrappedErrorMessage(line.error?.message) ?? "Codex couldn’t answer.")
        default:
            return .ignored
        }
    }

    private static func opencode(_ payload: String, knownServers: [String]) throws -> StreamChunk {
        guard let line = try? decoder.decode(OpenCodeLine.self, from: Data(payload.utf8)) else { return .ignored }
        switch line.type {
        case "text":
            guard let text = line.part?.text, !text.isEmpty else { return .ignored }
            return .text(text)
        case "reasoning":
            return .activity(.thinking)
        case "tool_use":
            guard let part = line.part, let tool = part.tool else { return .ignored }
            let input = part.state?.input
            let activity = Activity.named(tool, query: input?.query, url: input?.url, knownServers: knownServers)
            // OpenCode's run mode cannot ask, so it turns down any tool its permissions would ask about
            // and says so in the tool's result. That shows up as an ask it settled itself.
            if part.state?.status == "error", let message = part.state?.error ?? part.state?.output,
               message.localizedCaseInsensitiveContains("rejected permission") {
                let detail = input?.command ?? input?.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? input?.url ?? input?.query
                return .prompt(AgentPrompt(id: part.callID ?? UUID().uuidString, kind: .permission(activity, detail: detail), resolution: .declinedByAgent))
            }
            return .activity(activity)
        case "error":
            throw LLMError.provider(line.error?.data?.message ?? line.error?.name ?? "OpenCode couldn’t answer.")
        default:
            return .ignored
        }
    }

    private static func unwrappedErrorMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: Data(message.utf8)),
           let nested = envelope.error?.message ?? envelope.message {
            return nested
        }
        return message
    }

    private static func ollama(_ payload: String) throws -> StreamChunk {
        let chunk = try decoder.decode(OllamaChunk.self, from: Data(payload.utf8))
        if let error = chunk.error { throw LLMError.provider(error) }
        if let content = chunk.message?.content, !content.isEmpty { return .text(content) }
        return chunk.done == true ? .finished : .ignored
    }
}

private nonisolated struct EventKind: Decodable {
    let type: String
}

private nonisolated struct ErrorDetail: Decodable {
    let message: String?
}

private nonisolated struct ErrorEnvelope: Decodable {
    let error: ErrorValue?
    let message: String?

    enum ErrorValue: Decodable {
        case detail(ErrorDetail)
        case text(String)

        var message: String? {
            switch self {
            case .detail(let detail): detail.message
            case .text(let text): text
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .detail(try container.decode(ErrorDetail.self))
            }
        }
    }
}

private nonisolated struct AnthropicEvent: Decodable {
    let type: String
    let delta: Delta?
    let contentBlock: ContentBlock?
    let error: ErrorDetail?

    struct ContentBlock: Decodable {
        let type: String
        let name: String?
    }

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let stopReason: String?
    }
}

private nonisolated struct ToolInput: Decodable {
    let query: String?
    let url: String?
    let command: String?
    let filePath: String?
}

private nonisolated struct ResponsesItemAdded: Decodable {
    let item: Item

    struct Item: Decodable {
        let type: String
    }
}

private nonisolated struct ResponsesTextDelta: Decodable {
    let delta: String
}

private nonisolated struct ResponsesFailure: Decodable {
    let response: Response

    struct Response: Decodable {
        let error: ErrorDetail?
    }
}

private nonisolated struct ChatCompletionChunk: Decodable {
    let choices: [Choice]?
    let error: ErrorDetail?

    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private nonisolated struct GeminiChunk: Decodable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let error: ErrorDetail?

    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
        let thought: Bool?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }
}

private nonisolated struct OllamaChunk: Decodable {
    let message: Message?
    let done: Bool?
    let error: String?

    struct Message: Decodable {
        let content: String?
    }
}

private nonisolated struct ClaudeCodeLine: Decodable {
    let type: String
    let event: AnthropicEvent?
    let message: Message?
    let isError: Bool?
    let result: String?

    struct Message: Decodable {
        let content: [Block]?
    }

    struct Block: Decodable {
        let type: String
        let name: String?
        let input: ToolInput?
    }
}

private nonisolated struct CodexLine: Decodable {
    let type: String
    let item: Item?
    let error: ErrorDetail?

    struct Item: Decodable {
        let type: String
        let text: String?
        let query: String?
        let server: String?
        let tool: String?
    }
}

private nonisolated struct OpenCodeLine: Decodable {
    let type: String
    let part: Part?
    let error: Failure?

    struct Part: Decodable {
        let text: String?
        let tool: String?
        let callID: String?
        let state: State?
    }

    struct State: Decodable {
        let status: String?
        let input: ToolInput?
        let output: String?
        let error: String?
    }

    struct Failure: Decodable {
        let name: String?
        let data: ErrorDetail?
    }
}
