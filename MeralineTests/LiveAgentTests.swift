import Foundation
import Testing
@testable import Meraline

struct AgentMemoryTests {
    private func request(_ texts: [String]) -> ChatRequest {
        ChatRequest(
            provider: .claudeCode,
            settings: ProviderSettings(model: "", baseURL: "claude", apiKey: "", isEnabled: true),
            systemPrompt: "",
            messages: texts.enumerated().map { ChatMessage(role: $0.offset.isMultiple(of: 2) ? .user : .assistant, text: $0.element) }
        )
    }

    @Test func aFollowUpGoesOnAndAnythingElseStartsOver() {
        var memory = AgentMemory()
        #expect(memory.plan(for: request(["Hi"])) == .fresh)
        memory.remember(request(["Hi"]), answer: "Hello.")
        #expect(memory.plan(for: request(["Hi", "Hello.", "And you?"])) == .followUp)
        // Ask Again asks the last question once more, without the answer the agent remembers.
        #expect(memory.plan(for: request(["Hi"])) == .startOver)
        // Another provider answered in between.
        #expect(memory.plan(for: request(["Hi", "Hi there!", "And you?"])) == .startOver)
        memory.forget()
        #expect(memory.plan(for: request(["Hi", "Hi there!", "And you?"])) == .fresh)
    }

    @Test func aRewriteFollowsOnAndTheNextQuestionStartsOver() {
        var memory = AgentMemory()
        memory.remember(request(["Explain DNS"]), answer: "A long answer.")
        let rewrite = request(["Explain DNS", "A long answer.", "Make it shorter."])
        #expect(memory.plan(for: rewrite) == .followUp)
        memory.remember(rewrite, answer: "Short.")
        // The chat keeps the short answer in place of the long one, and never shows the instruction.
        #expect(memory.plan(for: request(["Explain DNS", "Short.", "Thanks, and IPv6?"])) == .startOver)
    }

    @Test func textAfterAToolStartsTheAnswerOverAsTheChatDoes() {
        var tracker = AnswerTracker()
        tracker.note(.text("Let me look that up."))
        tracker.note(.activity(.searching("Prague")))
        tracker.note(.text("It’s sunny"))
        tracker.note(.text(" in Prague."))
        #expect(tracker.answer == "It’s sunny in Prague.")
    }
}

/// The pool with stand-ins for claude and codex, shell scripts that speak just enough of their protocols and say
/// which process answered and how many questions it has had.
struct LiveAgentTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.live.\(UUID().uuidString)")

    /// Answers each line on stdin with its own process id and a count; a question with "hang" in it gets no answer.
    private static let claude = #"""
    #!/bin/sh
    n=0
    while IFS= read -r line; do
      case "$line" in *hang*) sleep 30; continue ;; esac
      n=$((n+1))
      printf '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"%s answer %s"}}}\n' "$$" "$n"
      printf '{"type":"result","subtype":"success","is_error":false,"result":"done"}\n'
    done
    """#

    /// Shakes hands, opens threads, and answers each turn with its thread and a count, over JSON-RPC.
    private static let codex = #"""
    #!/bin/sh
    threads=0
    turns=0
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
      case "$line" in
        *'"method":"initialize"'*) printf '{"id":%s,"result":{"userAgent":"fake"}}\n' "$id" ;;
        *'"method":"thread/start"'*)
          threads=$((threads+1))
          printf '{"id":%s,"result":{"thread":{"id":"thread-%s"}}}\n' "$id" "$threads"
          printf '{"method":"thread/started","params":{"thread":{"id":"thread-%s"}}}\n' "$threads" ;;
        *'"method":"turn/start"'*)
          turns=$((turns+1))
          printf '{"id":%s,"result":{"turn":{"id":"turn-%s"}}}\n' "$id" "$turns"
          printf '{"method":"item/started","params":{"item":{"type":"reasoning","id":"r"},"threadId":"thread-%s","turnId":"turn-%s"}}\n' "$threads" "$turns"
          printf '{"method":"item/agentMessage/delta","params":{"itemId":"m","delta":"thread-%s","threadId":"thread-%s","turnId":"turn-%s"}}\n' "$threads" "$threads" "$turns"
          printf '{"method":"item/agentMessage/delta","params":{"itemId":"m","delta":" turn-%s","threadId":"thread-%s","turnId":"turn-%s"}}\n' "$turns" "$threads" "$turns"
          printf '{"method":"turn/completed","params":{"threadId":"thread-%s","turn":{"id":"turn-%s","status":"completed","error":null}}}\n' "$threads" "$turns" ;;
      esac
    done
    """#

    private func script(_ text: String, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func request(_ provider: Provider, command: URL, workspace: URL?, _ texts: [String]) -> ChatRequest {
        ChatRequest(
            provider: provider,
            settings: ProviderSettings(model: "", baseURL: command.path, apiKey: "", isEnabled: true, allowsWebSearch: false, allowsMCP: false),
            systemPrompt: "Be brief.",
            messages: texts.enumerated().map { ChatMessage(role: $0.offset.isMultiple(of: 2) ? .user : .assistant, text: $0.element) },
            workspace: workspace
        )
    }

    private func answer(_ request: ChatRequest) async throws -> String {
        var text = ""
        for try await output in LiveAgents.shared.stream(request) {
            if case .text(let piece) = output { text += piece }
        }
        try Task.checkCancellation()
        return text
    }

    @Test(.timeLimit(.minutes(1))) func claudeCodeStaysForFollowUpsAndStartsOverOtherwise() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let command = try script(Self.claude, named: "claude")
        let workspace = try ChatWorkspace.make(in: root)
        defer { workspace.remove() }

        let first = try await answer(request(.claudeCode, command: command, workspace: workspace.url, ["Hi"]))
        let process = try #require(first.split(separator: " ").first)
        #expect(first == "\(process) answer 1")
        let followUp = try await answer(request(.claudeCode, command: command, workspace: workspace.url, ["Hi", first, "More"]))
        #expect(followUp == "\(process) answer 2", "the same process takes the follow-up")
        let again = try await answer(request(.claudeCode, command: command, workspace: workspace.url, ["Hi", first, "More"]))
        #expect(again.hasSuffix(" answer 1"), "asking the same question again starts a new process")
        #expect(!again.hasPrefix("\(process) "))
    }

    @Test(.timeLimit(.minutes(1))) func stoppingEndsTheAgent() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let command = try script(Self.claude, named: "claude")
        let workspace = try ChatWorkspace.make(in: root)
        defer { workspace.remove() }

        let first = try await answer(request(.claudeCode, command: command, workspace: workspace.url, ["Hi"]))
        let hanging = Task { try await answer(request(.claudeCode, command: command, workspace: workspace.url, ["Hi", first, "hang on"])) }
        try await Task.sleep(for: .milliseconds(300))
        hanging.cancel()
        await #expect(throws: CancellationError.self) { try await hanging.value }
        let next = try await answer(request(.claudeCode, command: command, workspace: workspace.url, ["Hi", first, "And now?"]))
        #expect(next.hasSuffix(" answer 1"), "a new process answers after Stop")
    }

    @Test(.timeLimit(.minutes(1))) func codexKeepsItsThreadForFollowUpsAndOpensAnotherOtherwise() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let command = try script(Self.codex, named: "codex")
        let workspace = try ChatWorkspace.make(in: root)
        defer { workspace.remove() }

        let first = try await answer(request(.codex, command: command, workspace: workspace.url, ["Hi"]))
        #expect(first == "thread-1 turn-1")
        let followUp = try await answer(request(.codex, command: command, workspace: workspace.url, ["Hi", first, "More"]))
        #expect(followUp == "thread-1 turn-2")
        let again = try await answer(request(.codex, command: command, workspace: workspace.url, ["Hi", first, "More"]))
        #expect(again == "thread-2 turn-3", "the same process opens a new thread to start over")
    }

    @Test(.timeLimit(.minutes(1))) func aWarmedUpCodexAnswersInTheThreadItOpened() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let command = try script(Self.codex, named: "codex")
        let workspace = try ChatWorkspace.make(in: root)
        defer { workspace.remove() }

        LiveAgents.shared.prewarm(request(.codex, command: command, workspace: workspace.url, ["…"]))
        let first = try await answer(request(.codex, command: command, workspace: workspace.url, ["Hi"]))
        #expect(first == "thread-1 turn-1")
    }

    @Test(.timeLimit(.minutes(1))) func aRequestWithoutAWorkspaceGetsAnAgentForOneAnswer() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let command = try script(Self.claude, named: "claude")
        let one = try await answer(request(.claudeCode, command: command, workspace: nil, ["Hi"]))
        let two = try await answer(request(.claudeCode, command: command, workspace: nil, ["Hi", one, "More"]))
        #expect(one.hasSuffix(" answer 1") && two.hasSuffix(" answer 1"))
    }
}
