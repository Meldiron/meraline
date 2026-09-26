import Foundation
import Testing
@testable import Meraline

struct AgentPromptTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.prompts.\(UUID().uuidString)")

    @Test func claudeCodeAsksForLeaveToWrite() throws {
        let line = ##"{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"Write","display_name":"Write","input":{"file_path":"/tmp/ws/note.md","content":"# Beta\n"},"description":"note.md","permission_suggestions":[],"tool_use_id":"toolu_1"}}"##
        guard case .prompt(let prompt) = try StreamDecoder.decode(line, from: .claudeCode) else {
            Issue.record("Claude Code's ask was not decoded")
            return
        }
        #expect(prompt.id == "req-1")
        #expect(prompt.kind == .permission(.tool("Write"), detail: "note.md"))
        #expect(prompt.isPending)
        #expect(prompt.kind.logDescription == "for leave to use Write")

        let allow = try JSONSerialization.jsonObject(with: prompt.claudeCodeResponse(.allow)) as? [String: Any]
        let response = allow?["response"] as? [String: Any]
        let inner = response?["response"] as? [String: Any]
        #expect(allow?["type"] as? String == "control_response")
        #expect(response?["subtype"] as? String == "success")
        #expect(response?["request_id"] as? String == "req-1")
        #expect(inner?["behavior"] as? String == "allow")
        #expect((inner?["updatedInput"] as? [String: Any])?["content"] as? String == "# Beta\n")
        #expect(try prompt.claudeCodeResponse(.allow).last == 0x0A)

        let deny = try JSONSerialization.jsonObject(with: prompt.claudeCodeResponse(.deny)) as? [String: Any]
        let denied = (deny?["response"] as? [String: Any])?["response"] as? [String: Any]
        #expect(denied?["behavior"] as? String == "deny")
        #expect((denied?["message"] as? String)?.isEmpty == false)
    }

    @Test func claudeCodeQuestionsCarryTheirChoices() throws {
        let line = #"{"type":"control_request","request_id":"req-2","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Alpha or Beta?","header":"Title","options":[{"label":"Alpha","description":"A"},{"label":"Beta","description":"B"}],"multiSelect":false}]},"requires_user_interaction":true}}"#
        guard case .prompt(let prompt) = try StreamDecoder.decode(line, from: .claudeCode) else {
            Issue.record("Claude Code's question was not decoded")
            return
        }
        let question = AgentPrompt.Question(
            header: "Title",
            text: "Alpha or Beta?",
            options: [.init(label: "Alpha", detail: "A"), .init(label: "Beta", detail: "B")]
        )
        #expect(prompt.kind == .question([question]))
        #expect(prompt.kind.logDescription == "a question")

        let answered = try JSONSerialization.jsonObject(with: prompt.claudeCodeResponse(.answers(["Alpha or Beta?": "Beta"]))) as? [String: Any]
        let inner = (answered?["response"] as? [String: Any])?["response"] as? [String: Any]
        let updated = inner?["updatedInput"] as? [String: Any]
        #expect(inner?["behavior"] as? String == "allow")
        #expect(updated?["answers"] as? [String: String] == ["Alpha or Beta?": "Beta"])
        #expect((updated?["questions"] as? [[String: Any]])?.count == 1)
        #expect(AgentAnswer.answers(["q": "a"]).resolution == .answered(["q": "a"]))
    }

    @Test func otherControlRequestsAreIgnored() throws {
        #expect(try StreamDecoder.decode(#"{"type":"control_request","request_id":"r","request":{"subtype":"hook_callback"}}"#, from: .claudeCode) == .ignored)
        let mcp = #"{"type":"control_request","request_id":"req-3","request":{"subtype":"can_use_tool","tool_name":"mcp__knowledge-rag__search_knowledge","input":{"query":"notes"}}}"#
        #expect(try StreamDecoder.decode(mcp, from: .claudeCode) == .prompt(AgentPrompt(
            id: "req-3",
            kind: .permission(.mcp(server: "knowledge-rag", tool: "search_knowledge"), detail: "notes"),
            input: Data(#"{"query":"notes"}"#.utf8)
        )))
    }

    @Test func openCodeReportsTheAsksItTurnedDown() throws {
        let declined = #"{"type":"tool_use","part":{"type":"tool","tool":"bash","callID":"call_1","state":{"status":"error","input":{"command":"ls -la"},"error":"The user rejected permission to use this specific tool call."}}}"#
        guard case .prompt(let prompt) = try StreamDecoder.decode(declined, from: .opencode) else {
            Issue.record("OpenCode's declined ask was not decoded")
            return
        }
        #expect(prompt.id == "call_1")
        #expect(prompt.kind == .permission(.running, detail: "ls -la"))
        #expect(prompt.resolution == .declinedByAgent)
        #expect(!prompt.isPending)
        let running = #"{"type":"tool_use","part":{"type":"tool","tool":"bash","callID":"call_1","state":{"status":"running","input":{"command":"ls -la"}}}}"#
        #expect(try StreamDecoder.decode(running, from: .opencode) == .activity(.running))
        let failed = #"{"type":"tool_use","part":{"type":"tool","tool":"bash","callID":"call_2","state":{"status":"error","input":{"command":"ls"},"error":"exit 1"}}}"#
        #expect(try StreamDecoder.decode(failed, from: .opencode) == .activity(.running))
    }

    @Test func requestsReadAsPhrases() {
        #expect(Activity.tool("Write").request == "use Write")
        #expect(Activity.searching("x").request == "search the web for “x”")
        #expect(Activity.mcp(server: "knowledge-rag", tool: "search_knowledge").request == "ask knowledge-rag to search knowledge")
        #expect(Activity.running.request == "run a command")
    }

    @MainActor @Test func anAskWaitsForTheAnswerAndTheAnswerGoesBack() async {
        let box = AnswerBox()
        let prompt = AgentPrompt(id: "req-1", kind: .permission(.tool("Write"), detail: "note.md"))
        let session = ChatSession(preferences: GameTestSupport.preferences(), workspaceRoot: root) { _ in
            AsyncThrowingStream { continuation in
                box.continuation = continuation
                continuation.yield(.activity(.tool("Write")))
                continuation.yield(.prompt(prompt, AgentPromptResponder { box.record($0) }))
            }
        }
        session.draft = "Write a note"
        session.send()
        for _ in 0..<1_000 where session.turns.last?.pendingPrompt == nil { await Task.yield() }
        #expect(session.turns.last?.pendingPrompt == prompt)
        #expect(session.turns.last?.activity == nil)
        #expect(session.isStreaming)

        session.answer("req-1", with: .allow)
        #expect(box.answers == [.allow])
        #expect(session.turns.last?.pendingPrompt == nil)
        #expect(session.turns.last?.prompts.first?.resolution == .allowed)
        session.answer("req-1", with: .deny)
        #expect(box.answers == [.allow])

        box.continuation?.yield(.text("Done."))
        box.continuation?.finish()
        await GameTestSupport.settle(session)
        #expect(session.turns.last?.answer == "Done.")
        #expect(session.turns.last?.tools == [.tool("Write")])
        #expect(session.turns.last?.prompts.map(\.resolution) == [.allowed])
    }

    @MainActor @Test func stoppingDropsAPendingAsk() async {
        let box = AnswerBox()
        let prompt = AgentPrompt(id: "req-1", kind: .question([.init(text: "Alpha or Beta?")]))
        let session = ChatSession(preferences: GameTestSupport.preferences(), workspaceRoot: root) { _ in
            AsyncThrowingStream { continuation in
                box.continuation = continuation
                continuation.yield(.prompt(prompt, AgentPromptResponder { box.record($0) }))
            }
        }
        session.draft = "Which one?"
        session.send()
        for _ in 0..<1_000 where session.turns.last?.pendingPrompt == nil { await Task.yield() }
        #expect(session.turns.last?.pendingPrompt == prompt)
        session.stop()
        await GameTestSupport.settle(session)
        #expect(session.turns.isEmpty)
        #expect(session.draft == "Which one?")
        #expect(box.answers.isEmpty)
        session.answer("req-1", with: .deny)
        #expect(box.answers.isEmpty)
    }

    @Test func archivingKeepsOnlySettledAsks() throws {
        var turn = ChatSession.Turn(question: "Q", images: [])
        turn.answer = "A"
        turn.prompts = [
            AgentPrompt(id: "a", kind: .permission(.tool("Write"), detail: nil), resolution: .allowed),
            AgentPrompt(id: "b", kind: .permission(.tool("Edit"), detail: nil))
        ]
        let chat = try #require(ChatSession.archiving([turn], into: []).first)
        #expect(chat.turns.first?.prompts.map(\.id) == ["a"])
    }

    /// Runs the installed claude for real: it asks for leave to write in the chat's workspace, the test
    /// allows it, and the file is there afterwards.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil), .timeLimit(.minutes(1)))
    func installedClaudeCodeWritesInTheWorkspaceWhenAllowed() async throws {
        guard CommandLineClient.resolve("claude") != nil else { return }
        let workspace = try ChatWorkspace.make(in: root)
        defer { ChatWorkspace.removeAll(in: root) }
        let request = ChatRequest(
            provider: .claudeCode,
            settings: ProviderSettings(model: "haiku", baseURL: "claude", apiKey: "", isEnabled: true, allowsWebSearch: false, effort: .low, allowsMCP: false),
            systemPrompt: "Be brief.",
            messages: [ChatMessage(role: .user, text: "Write a file named hello.txt containing the word hello in the current folder, then reply with the single word done.")],
            workspace: workspace.url
        )
        var prompts: [AgentPrompt] = []
        var answer = ""
        for try await output in LLMClient.stream(request) {
            switch output {
            case .prompt(let prompt, let responder?):
                prompts.append(prompt)
                responder(.allow)
            case .text(let text):
                answer += text
            default:
                break
            }
        }
        #expect(prompts.contains { if case .permission(.tool("Write"), _) = $0.kind { true } else { false } }, "claude asked: \(prompts)")
        #expect(try String(contentsOf: workspace.url.appending(path: "hello.txt"), encoding: .utf8).lowercased().contains("hello"))
        #expect(answer.lowercased().contains("done"), "claude answered: \(answer)")
    }

    /// Runs the installed claude for real: it asks a question with choices, the test picks one, and the
    /// answer builds on the pick.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil), .timeLimit(.minutes(1)))
    func installedClaudeCodeAsksAndHearsTheAnswer() async throws {
        guard CommandLineClient.resolve("claude") != nil else { return }
        let workspace = try ChatWorkspace.make(in: root)
        defer { ChatWorkspace.removeAll(in: root) }
        let request = ChatRequest(
            provider: .claudeCode,
            settings: ProviderSettings(model: "haiku", baseURL: "claude", apiKey: "", isEnabled: true, allowsWebSearch: false, effort: .low, allowsMCP: false),
            systemPrompt: "Be brief.",
            messages: [ChatMessage(role: .user, text: "Use the AskUserQuestion tool to ask me whether the note should be titled Alpha or Beta, offering exactly those two options. Then reply with only the title I picked.")],
            workspace: workspace.url
        )
        var questions: [AgentPrompt.Question] = []
        var answer = ""
        for try await output in LLMClient.stream(request) {
            switch output {
            case .prompt(let prompt, let responder?):
                if case .question(let asked) = prompt.kind {
                    questions += asked
                    responder(.answers(Dictionary(uniqueKeysWithValues: asked.map { ($0.text, "Beta") })))
                } else {
                    responder(.deny)
                }
            case .text(let text):
                answer += text
            default:
                break
            }
        }
        #expect(questions.first?.options.map(\.label) == ["Alpha", "Beta"], "claude asked: \(questions)")
        #expect(answer.contains("Beta"), "claude answered: \(answer)")
    }
}

/// Collects what a prompt's responder was told, and holds the stream open until the test is done.
private nonisolated final class AnswerBox: @unchecked Sendable {
    private(set) var answers: [AgentAnswer] = []
    var continuation: AsyncThrowingStream<StreamOutput, Error>.Continuation?

    func record(_ answer: AgentAnswer) { answers.append(answer) }
}
