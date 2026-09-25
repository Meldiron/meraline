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

    @Test func claudeCodeSendsOneStreamJSONMessageWithoutTools() throws {
        let invocation = try CommandLineClient.invocation(for: request(
            .claudeCode,
            model: "sonnet",
            messages: [ChatMessage(role: .user, text: "What is this?", images: [image])]
        ))
        #expect(invocation.arguments.contains("--no-session-persistence"))
        let tools = try #require(invocation.arguments.firstIndex(of: "--tools"))
        #expect(invocation.arguments[tools + 1] == "")
        #expect(Array(invocation.arguments.suffix(2)) == ["--model", "sonnet"])

        let input = try #require(invocation.input)
        let line = try #require(JSONSerialization.jsonObject(with: input) as? [String: Any])
        let message = try #require(line["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "image")
        #expect(content.last?["text"] as? String == "What is this?")
    }

    @Test func codexRunsEphemerallyInAReadOnlySandbox() throws {
        let invocation = try CommandLineClient.invocation(for: request(
            .codex,
            messages: [ChatMessage(role: .user, text: "Hi", images: [image])]
        ))
        #expect(invocation.arguments == [
            "exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
            "--image", "image-1.png", "-"
        ])
        #expect(invocation.files["image-1.png"] == image.data)
        let prompt = String(decoding: try #require(invocation.input), as: UTF8.self)
        #expect(prompt.contains("Be brief."))
        #expect(prompt.hasSuffix("Hi"))
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
                settings: ProviderSettings(model: models[provider]!, baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: true),
                systemPrompt: "Reply with exactly one lowercase word.",
                messages: [ChatMessage(role: .user, text: "Say ready.")]
            )
            var answer = ""
            for try await text in LLMClient.stream(request) { answer += text }
            #expect(answer.lowercased().contains("ready"), "\(provider.name) answered: \(answer)")
        }
    }
}
