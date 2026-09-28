import Foundation

nonisolated enum StreamChunk: Equatable, Sendable {
    case text(String)
    case activity(Activity)
    /// The agent stopped to ask, or reports that it turned an ask of its own down.
    case prompt(AgentPrompt)
    /// The agent handed files to the person with `present_files` (see `PresentFilesServer`), by the paths it gave.
    case presented([String])
    case finished
    case ignored
}

nonisolated enum StreamOutput: Equatable, Sendable {
    case text(String)
    case activity(Activity)
    /// The responder carries the answer back; a prompt the agent settled itself has none.
    case prompt(AgentPrompt, AgentPromptResponder?)
    /// The agent handed files to the person, by the paths it gave; the chat finds them in its workspace.
    case presented([String])
    /// What the provider says the answer took so far (see `StreamDecoder.usage(in:from:)`): the fields it
    /// carries replace what was known, or, when `adds`, add to it.
    case usage(TokenUsage, adds: Bool)
}

/// What a provider's payload says an answer took, and whether it adds to earlier reports of the same answer or
/// replaces the fields it carries.
nonisolated struct UsageReport: Equatable, Sendable {
    let tokens: TokenUsage
    var adds = false
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
    /// The agent handing files to the person with Meraline's own `present_files`. Not in the trail of tools, since
    /// the files show under the answer.
    case presenting

    /// `knownServers` are the MCP servers the agent listed, so a tool can be shown under its server's
    /// name: Claude Code spells servers into tool names as `mcp__<server>__<tool>` and OpenCode as
    /// `<server>_<tool>`.
    static func named(_ name: String, query: String? = nil, url: String? = nil, knownServers: [String] = []) -> Activity {
        if PresentFilesServer.isTool(name) { return .presenting }
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
        case .presenting: "Handing over files"
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
        case .presenting: "hand over files"
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
        case .presenting: "Files"
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
        case .presenting: "arrow.down.doc"
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

    /// What `payload` says the answer took, if it says: read beside `decode`, since a Gemini chunk carries its
    /// text and its usage together, and OpenAI's last event the end of the stream and the usage. Input tokens
    /// are the ones not served from a cache, whatever the provider counts, and cached ones are `cacheRead`.
    static func usage(in payload: String, from provider: Provider) -> UsageReport? {
        let data = Data(payload.utf8)
        switch provider {
        case .anthropic:
            guard payload.contains("\"usage\""), let event = try? decoder.decode(AnthropicEvent.self, from: data) else { return nil }
            return anthropicUsage(event)
        case .openAI:
            guard payload.contains("response.completed"), let event = try? decoder.decode(ResponsesCompleted.self, from: data),
                  let usage = event.response.usage else { return nil }
            let cached = usage.inputTokensDetails?.cachedTokens ?? 0
            return UsageReport(tokens: TokenUsage(
                input: usage.inputTokens.map { max(0, $0 - cached) }, output: usage.outputTokens,
                cacheRead: usage.inputTokensDetails?.cachedTokens, model: event.response.model
            ))
        case .openRouter, .custom:
            guard payload.contains("\"usage\""), let chunk = try? decoder.decode(ChatCompletionChunk.self, from: data),
                  let usage = chunk.usage else { return nil }
            let cached = usage.promptTokensDetails?.cachedTokens ?? 0
            return UsageReport(tokens: TokenUsage(
                input: usage.promptTokens.map { max(0, $0 - cached) }, output: usage.completionTokens,
                cacheRead: usage.promptTokensDetails?.cachedTokens, cost: usage.cost, model: chunk.model
            ))
        case .gemini:
            guard payload.contains("usageMetadata"), let chunk = try? decoder.decode(GeminiChunk.self, from: data),
                  let usage = chunk.usageMetadata else { return nil }
            let cached = usage.cachedContentTokenCount ?? 0
            let output = usage.candidatesTokenCount.map { $0 + (usage.thoughtsTokenCount ?? 0) }
            return UsageReport(tokens: TokenUsage(
                input: usage.promptTokenCount.map { max(0, $0 - cached) }, output: output,
                cacheRead: usage.cachedContentTokenCount, model: chunk.modelVersion
            ))
        case .ollama:
            guard payload.contains("eval_count"), let chunk = try? decoder.decode(OllamaChunk.self, from: data),
                  chunk.promptEvalCount != nil || chunk.evalCount != nil else { return nil }
            return UsageReport(tokens: TokenUsage(input: chunk.promptEvalCount, output: chunk.evalCount, model: chunk.model))
        case .claudeCode:
            guard payload.contains("sage"), let line = try? decoder.decode(ClaudeCodeLine.self, from: data) else { return nil }
            switch line.type {
            case "stream_event":
                return line.event.flatMap(anthropicUsage)
            case "result":
                return claudeCodeUsage(line)
            default:
                return nil
            }
        case .codex:
            // The thread's running total; the turn's share is worked out where the turn is known (see `LiveAgents`).
            guard payload.contains("tokenUsage"), let line = try? decoder.decode(CodexTokenUsageLine.self, from: data),
                  line.method == "thread/tokenUsage/updated", let total = line.params?.tokenUsage?.total else { return nil }
            let cached = total.cachedInputTokens ?? 0
            return UsageReport(tokens: TokenUsage(
                input: total.inputTokens.map { max(0, $0 - cached) }, output: total.outputTokens,
                cacheRead: total.cachedInputTokens, cacheWrite: total.cacheWriteInputTokens
            ))
        case .opencode:
            guard payload.contains("step_finish"), let line = try? decoder.decode(OpenCodeStepLine.self, from: data),
                  line.type == "step_finish", let part = line.part else { return nil }
            let tokens = part.tokens
            return UsageReport(tokens: TokenUsage(
                input: tokens?.input, output: tokens.map { ($0.output ?? 0) + ($0.reasoning ?? 0) },
                cacheRead: tokens?.cache?.read, cacheWrite: tokens?.cache?.write, cost: part.cost
            ), adds: true)
        case .apple:
            return nil
        }
    }

    /// Anthropic's usage: the prompt's tokens with `message_start`, the answer's with `message_delta`, each
    /// replacing what it carries.
    private static func anthropicUsage(_ event: AnthropicEvent) -> UsageReport? {
        switch event.type {
        case "message_start":
            guard let usage = event.message?.usage else { return nil }
            return UsageReport(tokens: TokenUsage(
                input: usage.inputTokens, output: nil, cacheRead: usage.cacheReadInputTokens,
                cacheWrite: usage.cacheCreationInputTokens, model: event.message?.model
            ))
        case "message_delta":
            guard let usage = event.usage else { return nil }
            return UsageReport(tokens: TokenUsage(
                input: usage.inputTokens, output: usage.outputTokens,
                cacheRead: usage.cacheReadInputTokens, cacheWrite: usage.cacheCreationInputTokens
            ))
        default:
            return nil
        }
    }

    /// Claude Code's `result`: the turn's tokens by model, which its cost follows, and the cost of the turn.
    private static func claudeCodeUsage(_ line: ClaudeCodeLine) -> UsageReport? {
        if let models = line.modelUsage, !models.isEmpty {
            var tokens = TokenUsage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: line.totalCostUsd ?? 0)
            for (_, usage) in models {
                tokens.input! += usage.inputTokens ?? 0
                tokens.output! += usage.outputTokens ?? 0
                tokens.cacheRead! += usage.cacheReadInputTokens ?? 0
                tokens.cacheWrite! += usage.cacheCreationInputTokens ?? 0
            }
            if line.totalCostUsd == nil { tokens.cost = models.values.reduce(0) { $0 + ($1.costUSD ?? 0) } }
            tokens.model = models.max { ($0.value.outputTokens ?? 0) < ($1.value.outputTokens ?? 0) }?.key
            return UsageReport(tokens: tokens)
        }
        guard let usage = line.usage else { return nil }
        return UsageReport(tokens: TokenUsage(
            input: usage.inputTokens, output: usage.outputTokens, cacheRead: usage.cacheReadInputTokens,
            cacheWrite: usage.cacheCreationInputTokens, cost: line.totalCostUsd
        ))
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
            // Every message of a turn ends in `message_stop`, one that calls a tool included, and the ask for
            // that tool can come just before it. Only `result` ends the turn: finishing earlier would close
            // claude's stdin, and claude turns down whatever it is still waiting on.
            let chunk = try anthropic(event, knownServers: knownServers)
            return chunk == .finished ? .ignored : chunk
        case "assistant":
            let tools = line.message?.content?.filter { $0.type == "tool_use" } ?? []
            let handedOver = tools.filter { $0.name == PresentFilesServer.claudeCodeTool }.flatMap { $0.input?.filepaths ?? [] }
            if !handedOver.isEmpty { return .presented(handedOver) }
            guard let tool = tools.last, let name = tool.name else {
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

    /// A notification from Codex's app server (see `LiveAgents`): the answer's words as they come, what Codex is
    /// doing, the files it handed over, and the end of the turn. Responses to Meraline's own requests never get
    /// here.
    private static func codex(_ payload: String) throws -> StreamChunk {
        guard let line = try? decoder.decode(CodexNotification.self, from: Data(payload.utf8)) else { return .ignored }
        let params = line.params
        switch line.method {
        case "item/agentMessage/delta":
            guard let delta = params?.delta, !delta.isEmpty else { return .ignored }
            return .text(delta)
        case "item/started":
            guard let item = params?.item else { return .ignored }
            switch item.type {
            case "reasoning": return .activity(.thinking)
            case "commandExecution": return .activity(.running)
            case "webSearch": return .activity(.searching(item.query?.isEmpty == false ? item.query : nil))
            case "fileChange": return .activity(.tool("Edit"))
            case "mcpToolCall" where isPresentFiles(item): return .activity(.presenting)
            case "mcpToolCall": return .activity(.mcp(server: item.server ?? "an MCP server", tool: item.tool ?? ""))
            default: return .ignored
            }
        case "item/completed":
            guard let item = params?.item else { return .ignored }
            if isPresentFiles(item) {
                let paths = item.status == "completed" ? item.arguments?.filepaths ?? [] : []
                return paths.isEmpty ? .ignored : .presented(paths)
            }
            // A search says what it looked for once it is done, if it didn't when it began.
            if item.type == "webSearch", let query = item.query, !query.isEmpty { return .activity(.searching(query)) }
            return .ignored
        case "turn/completed":
            guard params?.turn?.status == "failed" else { return .finished }
            throw LLMError.provider(unwrappedErrorMessage(params?.turn?.error?.message) ?? "Codex couldn’t answer.")
        case "error":
            // Codex retries some failures on its own and says so first.
            guard params?.willRetry != true else { return .ignored }
            throw LLMError.provider(unwrappedErrorMessage(params?.error?.message) ?? "Codex couldn’t answer.")
        default:
            return .ignored
        }
    }

    /// Codex's call of `present_files`, which it names by server and tool.
    private static func isPresentFiles(_ item: CodexNotification.Item) -> Bool {
        item.type == "mcpToolCall" && item.server == PresentFilesServer.name && item.tool == PresentFilesServer.tool
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
            if tool == PresentFilesServer.openCodeTool, part.state?.status == "completed", let paths = input?.filepaths, !paths.isEmpty {
                return .presented(paths)
            }
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
    /// With `message_start`: the model and the prompt's tokens.
    let message: Message?
    /// With `message_delta`: the answer's tokens so far.
    let usage: Usage?

    struct ContentBlock: Decodable {
        let type: String
        let name: String?
    }

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let stopReason: String?
    }

    struct Message: Decodable {
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
    }
}

private nonisolated struct ResponsesCompleted: Decodable {
    let response: Response

    struct Response: Decodable {
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let inputTokensDetails: Details?
    }

    struct Details: Decodable {
        let cachedTokens: Int?
    }
}

/// Codex's `thread/tokenUsage/updated`: the thread's running total after each call to the model.
private nonisolated struct CodexTokenUsageLine: Decodable {
    let method: String
    let params: Params?

    struct Params: Decodable {
        let tokenUsage: TokenUsage?
    }

    struct TokenUsage: Decodable {
        let total: Breakdown?
    }

    struct Breakdown: Decodable {
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        let cacheWriteInputTokens: Int?
    }
}

/// OpenCode's `step_finish`: one step's tokens and cost, which add up over the answer.
private nonisolated struct OpenCodeStepLine: Decodable {
    let type: String
    let part: Part?

    struct Part: Decodable {
        let cost: Double?
        let tokens: Tokens?
    }

    struct Tokens: Decodable {
        let input: Int?
        let output: Int?
        let reasoning: Int?
        let cache: Cache?
    }

    struct Cache: Decodable {
        let read: Int?
        let write: Int?
    }
}

private nonisolated struct ToolInput: Decodable {
    let query: String?
    let url: String?
    let command: String?
    let filePath: String?
    /// What `present_files` hands over.
    let filepaths: [String]?

    private enum CodingKeys: String, CodingKey {
        case query, url, command, filePath, filepaths
    }

    /// Each field on its own, so an input that is odd in one way, or no object at all, still says what it can and
    /// never costs the whole line.
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        query = try? container?.decodeIfPresent(String.self, forKey: .query)
        url = try? container?.decodeIfPresent(String.self, forKey: .url)
        command = try? container?.decodeIfPresent(String.self, forKey: .command)
        filePath = try? container?.decodeIfPresent(String.self, forKey: .filePath)
        filepaths = try? container?.decodeIfPresent([String].self, forKey: .filepaths)
    }
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
    let model: String?
    /// With the last chunk, when the request asked for it; OpenRouter adds what the answer cost.
    let usage: Usage?

    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?
    }

    struct Delta: Decodable {
        let content: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let promptTokensDetails: Details?
        let cost: Double?
    }

    struct Details: Decodable {
        let cachedTokens: Int?
    }
}

private nonisolated struct GeminiChunk: Decodable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let error: ErrorDetail?
    /// The whole answer's tokens so far, with every chunk.
    let usageMetadata: UsageMetadata?
    let modelVersion: String?

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let thoughtsTokenCount: Int?
        let cachedContentTokenCount: Int?
    }

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
    let model: String?
    /// With the last chunk: the prompt's tokens and the answer's.
    let promptEvalCount: Int?
    let evalCount: Int?

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
    /// With `result`: what the turn cost, and its tokens by model.
    let totalCostUsd: Double?
    let usage: AnthropicEvent.Usage?
    let modelUsage: [String: ModelUsage]?

    struct ModelUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
        let costUSD: Double?
    }

    struct Message: Decodable {
        let content: [Block]?
    }

    struct Block: Decodable {
        let type: String
        let name: String?
        let input: ToolInput?
    }
}

private nonisolated struct CodexNotification: Decodable {
    let method: String
    let params: Params?

    /// Each field on its own, so one of an unexpected shape never costs the line, a turn's end least of all.
    struct Params: Decodable {
        let delta: String?
        let item: Item?
        let turn: Turn?
        let error: ErrorDetail?
        let willRetry: Bool?

        private enum CodingKeys: String, CodingKey {
            case delta, item, turn, error, willRetry
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            delta = try? container.decodeIfPresent(String.self, forKey: .delta)
            item = try? container.decodeIfPresent(Item.self, forKey: .item)
            turn = try? container.decodeIfPresent(Turn.self, forKey: .turn)
            error = try? container.decodeIfPresent(ErrorDetail.self, forKey: .error)
            willRetry = try? container.decodeIfPresent(Bool.self, forKey: .willRetry)
        }
    }

    /// Only what Meraline shows of an item, each field on its own, since items of other kinds use these names
    /// for other things.
    struct Item: Decodable {
        let type: String
        let query: String?
        let server: String?
        let tool: String?
        let arguments: ToolInput?
        let status: String?

        private enum CodingKeys: String, CodingKey {
            case type, query, server, tool, arguments, status
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            query = try? container.decodeIfPresent(String.self, forKey: .query)
            server = try? container.decodeIfPresent(String.self, forKey: .server)
            tool = try? container.decodeIfPresent(String.self, forKey: .tool)
            arguments = try? container.decodeIfPresent(ToolInput.self, forKey: .arguments)
            status = try? container.decodeIfPresent(String.self, forKey: .status)
        }
    }

    struct Turn: Decodable {
        let status: String?
        let error: ErrorDetail?
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
