import Foundation
import Testing
@testable import Meraline

struct ToolReasonTests {
    private let write = AgentPrompt(
        id: "req-1",
        kind: .permission(.tool("Write"), detail: "note.md"),
        input: Data(##"{"content":"# Note","file_path":"/tmp/ws/note.md"}"##.utf8)
    )

    @Test func readsTheChatTheAnswerSoFarAndTheCall() {
        var earlier = ChatSession.Turn(question: "Draft a note", images: [])
        earlier.answer = "Here is a draft."
        earlier.isComplete = true
        var current = ChatSession.Turn(question: "Save it", images: [], files: [FileAttachment(url: URL(fileURLWithPath: "/tmp/notes"), name: "notes", isFolder: true)])
        current.answer = "I'll save it as note.md."
        let question = ToolReason.question(for: write, in: [earlier, current])
        #expect(question.contains("Person: Draft a note"))
        #expect(question.contains("Claude Code: Here is a draft."))
        #expect(question.contains("Person: Save it (attached: notes/)"))
        #expect(question.contains("<answer>\nI'll save it as note.md.\n</answer>"))
        #expect(!question.contains("Claude Code: I'll save it"))
        #expect(question.contains("Claude Code now asks to use Write"))
        #expect(question.contains(#""file_path":"/tmp/ws/note.md""#))
    }

    @Test func readsOnlyTheLastTurnsAndCutsLongTexts() {
        let turns = (1...5).map { ChatSession.Turn(question: "Question \($0)", images: []) }
        let command = AgentPrompt(id: "r", kind: .permission(.running, detail: "ls"), input: Data(String(repeating: "x", count: 10_000).utf8))
        let question = ToolReason.question(for: command, in: turns)
        #expect(!question.contains("Question 2"))
        #expect(question.contains("Question 3") && question.contains("Question 5"))
        #expect(question.contains(String(repeating: "x", count: ToolReason.inputLimit) + "…"))
        #expect(!question.contains(String(repeating: "x", count: ToolReason.inputLimit + 1)))
    }

    @Test func readsAFinishedAnswerAndTheToolsItUsed() {
        var earlier = ChatSession.Turn(question: "Plan a day in Prague", images: [])
        earlier.answer = "Start at the castle."
        earlier.isComplete = true
        var asked = ChatSession.Turn(question: "What's the weather there this weekend?", images: [])
        asked.answer = "Sunny on Saturday, rain on Sunday."
        asked.tools = [.searching("Prague weather"), .reading("meteoblue.com"), .running]
        asked.isComplete = true
        let later = ChatSession.Turn(question: "And next week?", images: [])
        let question = ToolReason.question(forToolAt: 1, of: asked, in: [earlier, asked, later], agent: "Codex")
        #expect(question.contains("Person: Plan a day in Prague\n\nCodex: Start at the castle."))
        #expect(question.contains("Person: What's the weather there this weekend?\n</conversation>"))
        #expect(!question.contains("next week"))
        #expect(question.contains("Codex answered:\n<answer>\nSunny on Saturday, rain on Sunday.\n</answer>"))
        #expect(question.contains("used these tools, in order:\n1. Searching for “Prague weather”\n2. Reading meteoblue.com\n3. Running a command"))
        #expect(question.hasSuffix("Why did it read meteoblue.com (tool 2)?"))
    }

    @Test func namesTheOnlyToolWithoutItsNumber() {
        var turn = ChatSession.Turn(question: "Save it as a file", images: [])
        turn.answer = "Saved it as note.txt."
        turn.tools = [.tool("Write")]
        let question = ToolReason.question(forToolAt: 0, of: turn, in: [turn], agent: "Claude Code")
        #expect(question.contains("Claude Code used this tool:\n1. Using Write"))
        #expect(question.hasSuffix("Why did it use Write?"))
    }

    /// Any provider but Claude Code gets a request of its own: the question alone, with the Why? prompt, and
    /// neither the web, MCP servers, a workspace, nor files to hand over.
    @Test func asksTheProviderThatUsedTheTool() async throws {
        var turn = ChatSession.Turn(question: "Fix the typo in the README", images: [])
        turn.answer = "Fixed the title."
        turn.tools = [.running, .tool("Edit")]
        turn.provider = .codex
        let settings = ProviderSettings(model: "gpt-5-codex", baseURL: "codex", apiKey: "", isEnabled: true, knownMCPServers: ["notes"])
        let box = RequestBox()
        let reason = try await ToolReason.explain(toolAt: 0, of: turn, in: [turn], provider: .codex, settings: settings, instructions: "Say why.") { request in
            box.request = request
            return AsyncThrowingStream { continuation in
                continuation.yield(.activity(.thinking))
                continuation.yield(.text("Let me look."))
                continuation.yield(.prompt(AgentPrompt(id: "r", kind: .permission(.running, detail: "ls")), AgentPromptResponder { box.answers.append($0) }))
                continuation.yield(.activity(.running))
                continuation.yield(.text("It found the README "))
                continuation.yield(.text("before fixing it.\nMore."))
                continuation.finish()
            }
        }
        #expect(reason == "It found the README before fixing it.")
        #expect(box.answers == [.deny])
        let request = try #require(box.request)
        #expect(request.provider == .codex)
        #expect(request.systemPrompt == "Say why.")
        #expect(request.messages.map(\.text) == [ToolReason.question(forToolAt: 0, of: turn, in: [turn], agent: "Codex")])
        #expect(request.settings.model == "gpt-5-codex")
        #expect(!request.settings.allowsWebSearch)
        #expect(request.settings.allowedMCPServers.isEmpty)
        #expect(request.workspace == nil)
        #expect(!request.presentsFiles)
    }

    @Test func aReplyWithoutWordsIsNoReason() async {
        var turn = ChatSession.Turn(question: "Search for it", images: [])
        turn.tools = [.searching(nil)]
        let settings = ProviderSettings(model: "", baseURL: "opencode", apiKey: "", isEnabled: true)
        await #expect(throws: LLMError.self) {
            try await ToolReason.explain(toolAt: 0, of: turn, in: [turn], provider: .opencode, settings: settings) { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.text(" \n"))
                    continuation.finish()
                }
            }
        }
    }

    @Test func keepsTheReplysFirstLine() {
        #expect(ToolReason.firstLine(of: "\n  “It saves the note you asked for.”\nMore.") == "It saves the note you asked for.")
        #expect(ToolReason.firstLine(of: " \n\n") == nil)
    }

    @Test func runsWithoutToolsServersOrThinking() throws {
        let arguments = ToolReason.arguments(instructions: "Say why in Czech.")
        let prompt = try #require(arguments.firstIndex(of: "--system-prompt"))
        #expect(arguments[prompt + 1] == "Say why in Czech.")
        let tools = try #require(arguments.firstIndex(of: "--tools"))
        #expect(arguments[tools + 1] == "")
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(!arguments.contains("--permission-prompt-tool"))
        #expect(ToolReason.environment["MAX_THINKING_TOKENS"] == "0")
    }

    /// Runs the installed claude for real and expects one line that speaks of the file.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil), .timeLimit(.minutes(1)))
    func installedClaudeCodeSaysWhy() async throws {
        guard CommandLineClient.resolve("claude") != nil else { return }
        let turn = ChatSession.Turn(question: "Keep a note titled Groceries in the current folder.", images: [])
        let reason = try await ToolReason.explain(write, in: [turn], settings: ProviderSettings(model: "", baseURL: "claude", apiKey: "", isEnabled: true))
        #expect(!reason.contains("\n"))
        #expect(reason.lowercased().contains("note"), "claude said: \(reason)")
    }

    /// Runs each installed agent for real, as a tool's Why? does, and expects one line that speaks of the fix.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil), .timeLimit(.minutes(3)))
    func installedAgentsSayWhyTheyUsedATool() async throws {
        var turn = ChatSession.Turn(question: "Fix the typo in the title of README.md.", images: [])
        turn.answer = "Fixed: the title now reads “Getting Started” instead of “Getting Stared”."
        turn.tools = [.running, .tool("Edit")]
        let models: [Provider: String] = [.claudeCode: "", .codex: "", .opencode: "opencode/big-pickle"]
        for provider in Provider.commandLineTools where CommandLineClient.resolve(provider.defaultBaseURL) != nil {
            let settings = ProviderSettings(model: models[provider]!, baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: true, effort: .low)
            let reason = try await ToolReason.explain(toolAt: 1, of: turn, in: [turn], provider: provider, settings: settings)
            #expect(!reason.contains("\n"))
            #expect(["readme", "typo", "title", "stared"].contains { reason.lowercased().contains($0) }, "\(provider.name) said: \(reason)")
        }
    }

    /// Why? runs while the agent's own run waits on its ask with its pipes open and quiet. A read of one pipe
    /// must not hold up another, or the reason never arrives.
    @Test(.timeLimit(.minutes(1))) func aQuietRunDoesNotHoldUpAnother() async throws {
        let quiet = Task { try await CommandLineClient.output(of: URL(fileURLWithPath: "/bin/sleep"), arguments: ["4"], timeout: .seconds(10)) }
        try await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        let said = try await CommandLineClient.output(of: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data("why\n".utf8), timeout: .seconds(10))
        #expect(said == "why\n")
        #expect(ContinuousClock.now - start < .seconds(2))
        _ = try await quiet.value
    }
}

/// What the provider was asked, and what its asks were told.
private nonisolated final class RequestBox: @unchecked Sendable {
    var request: ChatRequest?
    var answers: [AgentAnswer] = []
}
