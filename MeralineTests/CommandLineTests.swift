import Foundation
import Testing
@testable import Meraline

struct CommandLineTests {
    private func request(_ provider: Provider, model: String = "", messages: [ChatMessage]) -> ChatRequest {
        ChatRequest(
            provider: provider,
            settings: ProviderSettings(model: model, baseURL: "/bin/echo", apiKey: "", isEnabled: true),
            systemPrompt: "Be brief.",
            messages: messages
        )
    }

    private let image = ImageAttachment(mediaType: "image/png", data: Data([1, 2, 3]))

    @Test func commandLineToolsNeedOnlyToBeEnabled() {
        #expect(ProviderSettings(model: "", baseURL: "claude", apiKey: "", isEnabled: true).isReady(for: .claudeCode))
        #expect(!ProviderSettings(model: "", baseURL: "claude", apiKey: "", isEnabled: false).isReady(for: .claudeCode))
    }

    @Test func resolvesAbsolutePathsAndRejectsMissingCommands() {
        #expect(CommandLineClient.resolve("/bin/echo")?.path == "/bin/echo")
        #expect(CommandLineClient.resolve("/definitely/not/here") == nil)
        #expect(CommandLineClient.resolve("meraline-missing-command") == nil)
    }

    @Test func missingCommandIsReported() {
        var missing = request(.codex, messages: [ChatMessage(role: .user, text: "Hi")])
        missing = ChatRequest(
            provider: missing.provider,
            settings: ProviderSettings(model: "", baseURL: "meraline-missing-command", apiKey: "", isEnabled: true),
            systemPrompt: missing.systemPrompt,
            messages: missing.messages
        )
        #expect(throws: LLMError.commandNotFound(.codex, "meraline-missing-command")) {
            try CommandLineClient.invocation(for: missing)
        }
    }

    @Test func claudeCodeSendsOneStreamJSONMessageAndAsksOverStdin() throws {
        let invocation = try CommandLineClient.invocation(for: request(
            .claudeCode,
            model: "sonnet",
            messages: [ChatMessage(role: .user, text: "What is this?", images: [image])]
        ))
        #expect(invocation.arguments.contains("--no-session-persistence"))
        let tools = try #require(invocation.arguments.firstIndex(of: "--tools"))
        #expect(invocation.arguments[tools + 1] == "WebSearch,WebFetch,Read,Write,Edit,Glob,Grep,Bash,Skill,AskUserQuestion")
        let prompts = try #require(invocation.arguments.firstIndex(of: "--permission-prompt-tool"))
        #expect(invocation.arguments[prompts + 1] == "stdio")
        let allowed = try #require(invocation.arguments.firstIndex(of: "--allowedTools"))
        #expect(Array(invocation.arguments[(allowed + 1)...(allowed + 2)]) == ["WebSearch", "WebFetch"])
        let model = try #require(invocation.arguments.firstIndex(of: "--model"))
        #expect(invocation.arguments[model + 1] == "sonnet")
        #expect(!invocation.arguments.contains("--effort"))

        let input = try #require(invocation.input)
        let line = try #require(JSONSerialization.jsonObject(with: input) as? [String: Any])
        let message = try #require(line["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "image")
        #expect(content.last?["text"] as? String == "What is this?")
    }

    @Test func claudeCodeCanRunWithoutToolsAndWithLowEffort() throws {
        let invocation = try CommandLineClient.invocation(for: ChatRequest(
            provider: .claudeCode,
            settings: ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true, allowsWebSearch: false, effort: .low),
            systemPrompt: "Be brief.",
            messages: [ChatMessage(role: .user, text: "Hi")]
        ))
        let tools = try #require(invocation.arguments.firstIndex(of: "--tools"))
        #expect(invocation.arguments[tools + 1] == "Read,Write,Edit,Glob,Grep,Bash,Skill,AskUserQuestion")
        #expect(!invocation.arguments.contains("--allowedTools"))
        let effort = try #require(invocation.arguments.firstIndex(of: "--effort"))
        #expect(invocation.arguments[effort + 1] == "low")
    }

    @Test func effortMapsToEachTool() throws {
        let settings = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true, effort: .high)
        let messages = [ChatMessage(role: .user, text: "Hi")]
        let codex = try CommandLineClient.invocation(for: ChatRequest(provider: .codex, settings: settings, systemPrompt: "", messages: messages))
        #expect(codex.arguments.contains("model_reasoning_effort=\"high\""))
        let opencode = try CommandLineClient.invocation(for: ChatRequest(provider: .opencode, settings: settings, systemPrompt: "", messages: messages))
        let variant = try #require(opencode.arguments.firstIndex(of: "--variant"))
        #expect(opencode.arguments[variant + 1] == "high")
    }

    @Test func decodesActivities() throws {
        let thinking = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}"#
        #expect(try StreamDecoder.decode(thinking, from: .claudeCode) == .activity(.thinking))
        let toolStart = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t","name":"WebSearch","input":{}}}}"#
        #expect(try StreamDecoder.decode(toolStart, from: .claudeCode) == .activity(.searching(nil)))
        let toolInput = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"WebFetch","input":{"url":"https://www.prague.eu/events","prompt":"x"}}]}}"#
        #expect(try StreamDecoder.decode(toolInput, from: .claudeCode) == .activity(.reading("www.prague.eu")))
        let command = #"{"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"ls","status":"in_progress"}}"#
        #expect(try StreamDecoder.decode(command, from: .codex) == .activity(.running))
        let tool = #"{"type":"tool_use","part":{"type":"tool","tool":"websearch","state":{"status":"completed","input":{"query":"Prague events"}}}}"#
        #expect(try StreamDecoder.decode(tool, from: .opencode) == .activity(.searching("Prague events")))
        #expect(Activity.searching("Prague events").title == "Searching for “Prague events”")
    }

    @Test func codexRunsEphemerallyInAWorkspaceWriteSandbox() throws {
        let invocation = try CommandLineClient.invocation(for: request(
            .codex,
            messages: [ChatMessage(role: .user, text: "Hi", images: [image])]
        ))
        #expect(invocation.arguments == [
            "exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "workspace-write",
            "--config", "web_search=\"live\"",
            "--image", "image-1.png", "-"
        ])
        #expect(invocation.files["image-1.png"] == image.data)
        let prompt = String(decoding: try #require(invocation.input), as: UTF8.self)
        #expect(prompt.contains("Be brief."))
        #expect(prompt.hasSuffix("Hi"))
    }

    @Test func codexWebSearchFollowsTheToggle() throws {
        let messages = [ChatMessage(role: .user, text: "Hi")]
        let off = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true, allowsWebSearch: false)
        let quiet = try CommandLineClient.invocation(for: ChatRequest(provider: .codex, settings: off, systemPrompt: "", messages: messages))
        #expect(quiet.arguments.contains("web_search=\"disabled\""))
        #expect(!quiet.arguments.contains("web_search=\"live\""))
        let on = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true, allowsWebSearch: true)
        let searching = try CommandLineClient.invocation(for: ChatRequest(provider: .codex, settings: on, systemPrompt: "", messages: messages))
        #expect(searching.arguments.contains("web_search=\"live\""))
        #expect(Provider.codex.supportsWebSearch && Provider.claudeCode.supportsWebSearch && !Provider.opencode.supportsWebSearch)
    }

    @Test func openCodePassesThePromptAfterTheOptions() throws {
        let invocation = try CommandLineClient.invocation(for: request(
            .opencode,
            model: "opencode/big-pickle",
            messages: [ChatMessage(role: .user, text: "Hi")]
        ))
        #expect(Array(invocation.arguments.prefix(5)) == ["run", "--format", "json", "--model", "opencode/big-pickle"])
        #expect(invocation.arguments[invocation.arguments.count - 2] == "--")
        #expect(invocation.input == nil)
    }

    @Test func followUpsIncludeTheConversation() {
        let transcript = CommandLineClient.transcript(of: [
            ChatMessage(role: .user, text: "Capital of France?"),
            ChatMessage(role: .assistant, text: "Paris."),
            ChatMessage(role: .user, text: "Population?")
        ])
        #expect(transcript.contains("User: Capital of France?"))
        #expect(transcript.contains("Assistant: Paris."))
        #expect(transcript.hasSuffix("Population?"))
    }

    @Test func decodesClaudeCodeLines() throws {
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ready"}},"session_id":"s"}"#
        #expect(try StreamDecoder.decode(delta, from: .claudeCode) == .text("ready"))
        let assistant = #"{"type":"assistant","message":{"content":[{"type":"text","text":"ready"}]}}"#
        #expect(try StreamDecoder.decode(assistant, from: .claudeCode) == .ignored)
        #expect(throws: LLMError.provider("Not logged in")) {
            try StreamDecoder.decode(#"{"type":"result","subtype":"error","is_error":true,"result":"Not logged in"}"#, from: .claudeCode)
        }
        #expect(try StreamDecoder.decode("Warning: something", from: .claudeCode) == .ignored)
    }

    @Test func decodesCodexLines() throws {
        let message = #"{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"ready"}}"#
        #expect(try StreamDecoder.decode(message, from: .codex) == .text("ready"))
        let warning = #"{"type":"item.completed","item":{"id":"item_0","type":"error","message":"deprecated"}}"#
        #expect(try StreamDecoder.decode(warning, from: .codex) == .ignored)
        let failure = #"{"type":"turn.failed","error":{"message":"{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Model not supported.\"}}"}}"#
        #expect(throws: LLMError.provider("Model not supported.")) { try StreamDecoder.decode(failure, from: .codex) }
    }

    @Test func decodesOpenCodeLines() throws {
        let text = #"{"type":"text","sessionID":"s","part":{"type":"text","text":"ready"}}"#
        #expect(try StreamDecoder.decode(text, from: .opencode) == .text("ready"))
        let error = #"{"type":"error","error":{"name":"APIError","data":{"message":"Subscription required.","statusCode":403}}}"#
        #expect(throws: LLMError.provider("Subscription required.")) { try StreamDecoder.decode(error, from: .opencode) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil))
    func installedCommandLineToolsAnswer() async throws {
        let models: [Provider: String] = [.claudeCode: "", .codex: "", .opencode: "opencode/big-pickle"]
        for provider in Provider.commandLineTools where CommandLineClient.resolve(provider.defaultBaseURL) != nil {
            let request = ChatRequest(
                provider: provider,
                settings: ProviderSettings(model: models[provider]!, baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: true, effort: .low),
                systemPrompt: "Reply with exactly one lowercase word.",
                messages: [ChatMessage(role: .user, text: "Say ready.")]
            )
            var answer = ""
            for try await output in LLMClient.stream(request) {
                if case .text(let text) = output { answer += text }
            }
            #expect(answer.lowercased().contains("ready"), "\(provider.name) answered: \(answer)")
        }
    }
}

struct LineReaderTests {
    /// A line reaches the reader while the writer is still open, as an agent's question does while it
    /// waits for the answer.
    @Test(.timeLimit(.minutes(1))) func linesArriveBeforeThePipeCloses() async throws {
        let pipe = Pipe()
        var lines = CommandLineClient.lines(of: pipe.fileHandleForReading).makeAsyncIterator()
        try pipe.fileHandleForWriting.write(contentsOf: Data("{\"type\":\"control_request\"}\npart".utf8))
        #expect(await lines.next() == #"{"type":"control_request"}"#)
        try pipe.fileHandleForWriting.write(contentsOf: Data("ial é\r\nlast".utf8))
        #expect(await lines.next() == "partial é")
        try pipe.fileHandleForWriting.close()
        #expect(await lines.next() == "last")
        #expect(await lines.next() == nil)
    }
}
