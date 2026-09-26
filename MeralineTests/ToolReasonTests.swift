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

    @Test func keepsTheReplysFirstLine() {
        #expect(ToolReason.firstLine(of: "\n  “It saves the note you asked for.”\nMore.") == "It saves the note you asked for.")
        #expect(ToolReason.firstLine(of: " \n\n") == nil)
    }

    @Test func runsWithoutToolsServersOrThinking() throws {
        let arguments = ToolReason.arguments
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
