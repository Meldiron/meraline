import Foundation
import Testing
@testable import Meraline

struct MCPServerTests {
    private func settings(known: [String] = [], off: Set<String> = [], allows: Bool = true) -> ProviderSettings {
        ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true, allowsMCP: allows, disabledMCPServers: off, knownMCPServers: known)
    }

    private let hi = [ChatMessage(role: .user, text: "Hi")]

    @Test func parsesClaudeCodeList() {
        let output = """
        Checking MCP server health…

        claude.ai Claude Docs: https://api.anthropic.com/v1/pages/mcp - ✔ Connected
        knowledge-rag: /Users/me/.local/bin/knowledge-rag  - ✔ Connected
        vencord: node --experimental-sqlite server.mjs - ✘ Failed to connect
        docs: npx -y docs-server - ⏸ Pending approval
        """
        let servers = MCPServerDiscovery.parseClaudeCode(output)
        #expect(servers.map(\.name) == ["claude.ai Claude Docs", "knowledge-rag", "vencord", "docs"])
        #expect(servers[0].target == "https://api.anthropic.com/v1/pages/mcp")
        #expect(servers[0].status == .connected)
        #expect(servers[1].target == "/Users/me/.local/bin/knowledge-rag")
        #expect(servers[2].status == .failed(nil))
        #expect(servers[3].status == .pendingApproval)
        #expect(MCPServerDiscovery.parseClaudeCode("No MCP servers configured. Use `claude mcp add` to add a server.").isEmpty)
    }

    @Test func parsesCodexList() throws {
        let json = #"""
        [{"name":"appwrite","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.appwrite.io/mcp"},"auth_status":"not_logged_in"},
         {"name":"computer-use","enabled":false,"transport":{"type":"stdio","command":"./Client","args":["mcp"]},"auth_status":"unsupported"},
         {"name":"node_repl","enabled":true,"transport":{"type":"stdio","command":"/opt/node_repl","args":[]},"auth_status":"unsupported"}]
        """#
        let servers = try MCPServerDiscovery.parseCodex(Data(json.utf8))
        #expect(servers.map(\.name) == ["appwrite", "computer-use", "node_repl"])
        #expect(servers[0].status == .needsSignIn)
        #expect(servers[0].target == "https://mcp.appwrite.io/mcp")
        #expect(servers[1].status == .disabledByAgent)
        #expect(servers[1].target == "./Client mcp")
        #expect(servers[2].status == .configured)
        #expect(MCPServerDiscovery.arguments(for: .codex) == ["mcp", "list", "--json"])
        #expect(MCPServerDiscovery.arguments(for: .claudeCode) == ["mcp", "list"])
    }

    @Test func parsesOpenCodeList() {
        let output = """
        \u{1B}[0m
        ┌  MCP Servers
        │
        ●  ✓ probe-stdio \u{1B}[90mconnected
        │      \u{1B}[90m/Users/me/.local/bin/knowledge-rag
        │
        ●  ✗ demo-remote \u{1B}[90mfailed
        │      SSE error: Was there a typo in the url or port?
        │      \u{1B}[90mhttps://example.invalid/mcp
        │
        ●  ○ demo-local \u{1B}[90mdisabled
        │      \u{1B}[90m/usr/bin/true
        │
        └  3 server(s)
        """
        let servers = MCPServerDiscovery.parseOpenCode(output)
        #expect(servers.map(\.name) == ["probe-stdio", "demo-remote", "demo-local"])
        #expect(servers[0].status == .connected)
        #expect(servers[0].target == "/Users/me/.local/bin/knowledge-rag")
        #expect(servers[1].status == .failed("SSE error: Was there a typo in the url or port?"))
        #expect(servers[1].target == "https://example.invalid/mcp")
        #expect(servers[2].status == .disabledByAgent)
        #expect(servers[2].target == "/usr/bin/true")
        let none = "┌  MCP Servers\n│\n▲  No MCP servers configured\n│\n└  Add servers with: opencode mcp add"
        #expect(MCPServerDiscovery.parseOpenCode(none).isEmpty)
    }

    @Test func serverNamesFollowEachAgent() {
        #expect(MCPServer.toolPrefix(for: "claude.ai Claude Docs") == "claude_ai_Claude_Docs")
        #expect(MCPServer.toolPrefix(for: "knowledge-rag") == "knowledge-rag")
        #expect(MCPServer.humanized("search_knowledge") == "search knowledge")
        #expect(CommandLineClient.tomlKey("node_repl") == "node_repl")
        #expect(CommandLineClient.tomlKey("claude.ai Docs") == "\"claude.ai Docs\"")
    }

    @Test func mcpToolsBecomeActivities() throws {
        let known = ["claude.ai Claude Docs", "knowledge-rag"]
        let activity = Activity.mcp(server: "knowledge-rag", tool: "search_knowledge")
        #expect(Activity.named("mcp__knowledge-rag__search_knowledge") == activity)
        #expect(Activity.named("mcp__claude_ai_Claude_Docs__guide", knownServers: known) == .mcp(server: "claude.ai Claude Docs", tool: "guide"))
        #expect(Activity.named("knowledge-rag_search_knowledge", knownServers: known) == activity)
        #expect(Activity.named("knowledge-rag_search_knowledge") == .tool("knowledge-rag_search_knowledge"))
        #expect(Activity.named("WebSearch", query: "x", knownServers: known) == .searching("x"))
        #expect(activity.title == "Asking knowledge-rag to search knowledge")
        #expect(activity.label == "knowledge-rag: search knowledge")
        #expect(Activity.searching("x").label == "Web search")
        #expect(Activity.reading("prague.eu").label == "prague.eu")

        let claude = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"mcp__knowledge-rag__search_knowledge","input":{"query":"x"}}]}}"#
        #expect(try StreamDecoder.decode(claude, from: .claudeCode) == .activity(activity))
        let start = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t","name":"mcp__claude_ai_Claude_Docs__guide","input":{}}}}"#
        #expect(try StreamDecoder.decode(start, from: .claudeCode, knownServers: known) == .activity(.mcp(server: "claude.ai Claude Docs", tool: "guide")))
        let codex = #"{"type":"item.started","item":{"id":"item_3","type":"mcp_tool_call","server":"knowledge-rag","tool":"search_knowledge","arguments":{},"status":"in_progress"}}"#
        #expect(try StreamDecoder.decode(codex, from: .codex) == .activity(activity))
        let opencode = #"{"type":"tool_use","part":{"type":"tool","tool":"knowledge-rag_search_knowledge","state":{"status":"running","input":{}}}}"#
        #expect(try StreamDecoder.decode(opencode, from: .opencode, knownServers: ["knowledge-rag"]) == .activity(activity))
    }

    @Test func claudeCodeNamesEachAllowedServer() throws {
        let request = ChatRequest(
            provider: .claudeCode,
            settings: settings(known: ["knowledge-rag", "claude.ai Claude Docs", "vencord"], off: ["vencord"]),
            systemPrompt: "",
            messages: hi
        )
        let arguments = try CommandLineClient.invocation(for: request).arguments
        #expect(!arguments.contains("--strict-mcp-config"))
        let allowed = try #require(arguments.firstIndex(of: "--allowedTools"))
        #expect(Array(arguments[(allowed + 1)...(allowed + 4)]) == ["WebSearch", "WebFetch", "mcp__knowledge-rag", "mcp__claude_ai_Claude_Docs"])
        let denied = try #require(arguments.firstIndex(of: "--disallowedTools"))
        #expect(arguments[denied + 1] == "mcp__vencord")
        #expect(arguments.last == "mcp__vencord")
    }

    @Test func claudeCodeKeepsMCPOffWithoutServers() throws {
        let none = try CommandLineClient.invocation(for: ChatRequest(provider: .claudeCode, settings: settings(), systemPrompt: "", messages: hi)).arguments
        #expect(none.contains("--strict-mcp-config"))
        #expect(!none.contains { $0.hasPrefix("mcp__") })
        let off = try CommandLineClient.invocation(for: ChatRequest(provider: .claudeCode, settings: settings(known: ["knowledge-rag"], allows: false), systemPrompt: "", messages: hi)).arguments
        #expect(off.contains("--strict-mcp-config"))
        #expect(!off.contains("--disallowedTools"))
        #expect(settings(known: ["a", "b"], off: ["a"]).allowedMCPServers == ["b"])
        #expect(settings(known: ["a", "b"], allows: false).allowedMCPServers.isEmpty)
    }

    @Test func codexTurnsServersOffThroughConfigOverrides() throws {
        let one = try CommandLineClient.invocation(for: ChatRequest(provider: .codex, settings: settings(known: ["appwrite", "node_repl"], off: ["node_repl"]), systemPrompt: "", messages: hi)).arguments
        #expect(one.contains("mcp_servers.node_repl.enabled=false"))
        #expect(!one.contains { $0.contains("appwrite") })
        let all = try CommandLineClient.invocation(for: ChatRequest(provider: .codex, settings: settings(known: ["appwrite"], allows: false), systemPrompt: "", messages: hi)).arguments
        #expect(all.contains("mcp_servers={}"))
        #expect(!all.contains { $0.contains("appwrite") })
    }

    @Test func openCodeTurnsServersOffThroughInlineConfig() throws {
        let one = try CommandLineClient.invocation(for: ChatRequest(provider: .opencode, settings: settings(known: ["a", "b"], off: ["b"]), systemPrompt: "", messages: hi))
        #expect(one.environment["OPENCODE_CONFIG_CONTENT"] == #"{"mcp":{"b":{"enabled":false}}}"#)
        let all = try CommandLineClient.invocation(for: ChatRequest(provider: .opencode, settings: settings(known: ["a", "b"], allows: false), systemPrompt: "", messages: hi))
        #expect(all.environment["OPENCODE_CONFIG_CONTENT"] == #"{"mcp":{"a":{"enabled":false},"b":{"enabled":false}}}"#)
        let none = try CommandLineClient.invocation(for: ChatRequest(provider: .opencode, settings: settings(known: ["a"]), systemPrompt: "", messages: hi))
        #expect(none.environment.isEmpty)
    }

    @Test func theTrailKeepsEachToolOnce() {
        var tools: [Activity] = []
        let search = Activity.mcp(server: "knowledge-rag", tool: "search_knowledge")
        for activity in [
            .thinking, .searching(nil), .searching("Prague events"), .searching(nil), .searching("Prague weather"),
            search, search, .reading(nil), .reading("prague.eu"), .running, .running
        ] as [Activity] {
            ChatSession.record(activity, in: &tools)
        }
        #expect(tools == [.searching("Prague events"), .searching("Prague weather"), search, .reading("prague.eu"), .running])
    }

    @MainActor @Test func anAnswerRemembersTheToolsItUsed() async {
        let tool = Activity.mcp(server: "knowledge-rag", tool: "search_knowledge")
        let session = ChatSession(preferences: GameTestSupport.preferences()) { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.activity(.thinking))
                continuation.yield(.activity(tool))
                continuation.yield(.text("Found it."))
                continuation.finish()
            }
        }
        session.draft = "Where are my notes?"
        session.send()
        await GameTestSupport.settle(session)
        #expect(session.turns.last?.answer == "Found it.")
        #expect(session.turns.last?.tools == [tool])
        #expect(session.turns.last?.activity == nil)
        session.reset()
        #expect(session.history.first?.turns.first?.tools == [tool])
    }

    /// Runs the installed agents' own `mcp list` for real, so the process helper and the parsers meet
    /// live output. What each agent listed goes to the test log.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil))
    func installedAgentsListTheirMCPServers() async throws {
        for provider in Provider.commandLineTools where CommandLineClient.resolve(provider.defaultBaseURL) != nil {
            let servers = try await MCPServerDiscovery.list(for: provider, command: provider.defaultBaseURL)
            print("MCP e2e: \(provider.name) listed \(servers.map { "\($0.name) [\($0.status.title)] \($0.target)" })")
            #expect(servers.allSatisfy { !$0.name.isEmpty })
        }
    }

    @MainActor @Test func theRegistryRemembersServerNamesForQuestions() async {
        let preferences = GameTestSupport.preferences(withProvider: false)
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true, disabledMCPServers: ["vencord"])
        let registry = MCPServerRegistry { provider, command in
            #expect(provider == .claudeCode && command == "/bin/echo")
            return [
                MCPServer(name: "knowledge-rag", status: .connected),
                MCPServer(name: "vencord", status: .failed(nil)),
                MCPServer(name: "off", status: .disabledByAgent)
            ]
        }
        registry.refresh(.claudeCode, preferences: preferences)
        #expect(registry.refreshing.contains(.claudeCode))
        for _ in 0..<1_000 where registry.refreshing.contains(.claudeCode) { await Task.yield() }
        #expect(registry.servers[.claudeCode]?.count == 3)
        #expect(preferences[.claudeCode].knownMCPServers == ["knowledge-rag", "vencord"])
        #expect(preferences[.claudeCode].allowedMCPServers == ["knowledge-rag"])
        #expect(registry.failures[.claudeCode] == nil)

        let failing = MCPServerRegistry { _, _ in throw LLMError.provider("no such command") }
        failing.refresh(.codex, preferences: preferences)
        for _ in 0..<1_000 where failing.refreshing.contains(.codex) { await Task.yield() }
        #expect(failing.failures[.codex] == "no such command")
        #expect(failing.servers[.codex] == nil)
    }
}
