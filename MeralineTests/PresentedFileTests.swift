import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Meraline

@MainActor
struct PresentedFileTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.presented.\(UUID().uuidString)")

    /// A workspace with report.md, out/chart.csv, a folder, and a link that leads out of it.
    private func workspace() throws -> URL {
        let url = try ChatWorkspace.make(in: root).url
        try Data("# Report".utf8).write(to: url.appending(path: "report.md"))
        try FileManager.default.createDirectory(at: url.appending(path: "out/site"), withIntermediateDirectories: true)
        try Data("a,b".utf8).write(to: url.appending(path: "out/chart.csv"))
        try FileManager.default.createSymbolicLink(at: url.appending(path: "escape"), withDestinationURL: FileManager.default.homeDirectoryForCurrentUser)
        return url
    }

    // MARK: Which files

    @Test func pathsResolveInsideTheWorkspaceOnly() throws {
        let workspace = try workspace()
        defer { ChatWorkspace.removeAll(in: root) }
        let report = try PresentedFile.resolve("report.md", in: workspace)
        #expect(report.path == "report.md")
        #expect(report.name == "report.md")
        #expect(!report.isFolder)
        #expect(try PresentedFile.resolve(workspace.path + "/out/chart.csv", in: workspace).path == "out/chart.csv")
        #expect(try PresentedFile.resolve("./out/../report.md", in: workspace) == report)
        // The temporary folder is under /private, which an agent may spell out.
        #expect(try PresentedFile.resolve("/private" + workspace.path + "/report.md", in: workspace) == report)
        #expect(try PresentedFile.resolve("out/site", in: workspace).isFolder)

        #expect(throws: PresentedFile.Problem.missing("nope.pdf")) { try PresentedFile.resolve("nope.pdf", in: workspace) }
        #expect(throws: PresentedFile.Problem.outside("escape")) { try PresentedFile.resolve("escape", in: workspace) }
        #expect(throws: PresentedFile.Problem.outside("escape/.zshrc")) { try PresentedFile.resolve("escape/.zshrc", in: workspace) }
        #expect(throws: PresentedFile.Problem.outside("../other")) { try PresentedFile.resolve("../other", in: workspace) }
        #expect(throws: PresentedFile.Problem.outside("/etc/hosts")) { try PresentedFile.resolve("/etc/hosts", in: workspace) }
        #expect(throws: PresentedFile.Problem.workspace) { try PresentedFile.resolve(".", in: workspace) }
        #expect(throws: PresentedFile.Problem.missing(" ")) { try PresentedFile.resolve(" ", in: workspace) }
    }

    @Test func aCallHandsOverEachFileOnceAndSaysWhatWentWrong() throws {
        let workspace = try workspace()
        defer { ChatWorkspace.removeAll(in: root) }
        let (files, problems) = PresentedFile.handOver(["report.md", "report.md", workspace.path + "/report.md", "nope"], in: workspace)
        #expect(files.map(\.path) == ["report.md"])
        #expect(problems == [PresentedFile.Problem.missing("nope").message])
        #expect(PresentedFile.handOver([], in: workspace).files.isEmpty)
        let tooMany = PresentedFile.handOver(Array(repeating: "report.md", count: PresentedFile.limit + 1), in: workspace)
        #expect(tooMany.files.isEmpty)
        #expect(tooMany.problems.first?.contains("zip") == true)
    }

    @Test func openingNeverRunsAnything() {
        func opening(_ pathExtension: String, _ type: UTType? = nil, executable: Bool = false) -> PresentedFile.Opening {
            PresentedFile.opening(for: type ?? UTType(filenameExtension: pathExtension), pathExtension: pathExtension, isExecutable: executable)
        }
        #expect(opening("pdf") == .inDefaultApp)
        #expect(opening("md") == .inDefaultApp)
        #expect(opening("html") == .inDefaultApp)
        #expect(opening("txt", executable: true) == .inDefaultApp)
        // Scripts open as text, since their own app may run them.
        #expect(opening("py") == .asText)
        #expect(opening("js") == .asText)
        #expect(opening("sh", executable: true) == .asText)
        #expect(opening("command", executable: true) == .asText)
        // Apps, programs, and files that run or install something are only shown in Finder.
        #expect(opening("app", .applicationBundle) == .never)
        #expect(opening("", .unixExecutable, executable: true) == .never)
        #expect(opening("bin", .data, executable: true) == .never)
        #expect(PresentedFile.opening(for: nil, pathExtension: "", isExecutable: true) == .never)
        #expect(opening("terminal") == .never)
        #expect(opening("mobileconfig") == .never)
        #expect(opening("fileloc") == .never)
    }

    @Test func aFileLeavingForAnotherAppIsMarkedAsDownloaded() throws {
        let workspace = try workspace()
        defer { ChatWorkspace.removeAll(in: root) }
        let file = try PresentedFile.resolve("report.md", in: workspace)
        #expect(try URL(fileURLWithPath: file.url.path).resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties == nil)
        file.markAsDownloaded()
        let properties = try #require(URL(fileURLWithPath: file.url.path).resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        #expect(properties[kLSQuarantineAgentNameKey as String] as? String == "Meraline")
        #expect(file.summary.contains("·"))
        #expect(try PresentedFile.resolve("out/site", in: workspace).summary == "Folder")
        try FileManager.default.createDirectory(at: workspace.appending(path: "Tool.app/Contents"), withIntermediateDirectories: true)
        #expect(try !PresentedFile.resolve("Tool.app", in: workspace).summary.contains("·"))
    }

    @Test func savingNumbersANameThatIsTaken() throws {
        let workspace = try workspace()
        defer { ChatWorkspace.removeAll(in: root) }
        let downloads = root.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data().write(to: downloads.appending(path: "report.md"))
        let files = try ["report.md", "out/site"].map { try PresentedFile.resolve($0, in: workspace) }
        let names = PresentedFiles.copy(files, into: downloads).map { try? $0.get() }
        #expect(names == ["report 2.md", "site"])
        #expect(try String(contentsOf: downloads.appending(path: "report 2.md"), encoding: .utf8) == "# Report")
    }

    // MARK: Meraline's MCP server

    private func reply(_ message: String, in workspace: URL = URL(fileURLWithPath: "/tmp")) throws -> [String: Any]? {
        guard let data = PresentFilesServer.reply(to: Data(message.utf8), in: workspace) else { return nil }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theServerStartsOnlyWhenAskedTo() {
        #expect(PresentFilesServer.workspace(in: ["/Meraline", "--present-files-server", "/tmp/ws"])?.path == "/tmp/ws")
        #expect(PresentFilesServer.workspace(in: ["/Meraline"]) == nil)
        #expect(PresentFilesServer.workspace(in: ["/Meraline", "--present-files-server"]) == nil)
        #expect(PresentFilesServer.workspace(in: ["/Meraline", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
        let command = PresentFilesServer.command(for: URL(fileURLWithPath: "/tmp/ws"), executable: URL(fileURLWithPath: "/Applications/Meraline.app/Contents/MacOS/Meraline"))
        #expect(command?.arguments == ["--present-files-server", "/tmp/ws"])
    }

    @Test func theServerShakesHandsInTheAgentsVersion() throws {
        let hello = try #require(try reply(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#))
        let result = try #require(hello["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "meraline")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        let future = try #require(try reply(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        #expect((future["result"] as? [String: Any])?["protocolVersion"] as? String == PresentFilesServer.protocolVersions[0])
        #expect(try reply(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(try reply(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)?["result"] != nil)
    }

    @Test func theServerListsItsOneTool() throws {
        let list = try #require(try reply(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#))
        #expect(list["id"] as? String == "a")
        let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["name"] as? String == "present_files")
        let schema = try #require(tools[0]["inputSchema"] as? [String: Any])
        #expect(schema["required"] as? [String] == ["filepaths"])
        #expect((tools[0]["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true)
    }

    @Test func theServerSaysWhatItHandedOver() throws {
        let workspace = try workspace()
        defer { ChatWorkspace.removeAll(in: root) }
        func call(_ paths: String) throws -> (text: String, isError: Bool) {
            let answer = try #require(try reply(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"present_files","arguments":{"filepaths":\#(paths)}}}"#, in: workspace))
            let result = try #require(answer["result"] as? [String: Any])
            let content = try #require(result["content"] as? [[String: Any]])
            return (content.first?["text"] as? String ?? "", result["isError"] as? Bool ?? true)
        }
        let handed = try call(#"["report.md","out/chart.csv"]"#)
        #expect(!handed.isError)
        #expect(handed.text.contains("report.md, out/chart.csv"))
        let partly = try call(#"["report.md","/etc/hosts"]"#)
        #expect(partly.isError)
        #expect(partly.text.contains("report.md"))
        #expect(partly.text.contains("outside the working directory"))
        #expect(try call("[]").isError)
    }

    @Test func theServerTurnsDownWhatItDoesNotKnow() throws {
        let tool = try #require(try reply(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rm","arguments":{}}}"#))
        #expect((tool["error"] as? [String: Any])?["code"] as? Int == -32602)
        let method = try #require(try reply(#"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#))
        #expect((method["error"] as? [String: Any])?["code"] as? Int == -32601)
        let garbage = try #require(try reply("garbage"))
        #expect((garbage["error"] as? [String: Any])?["code"] as? Int == -32700)
        // A reply of the agent's own, which has no method, gets none.
        #expect(try reply(#"{"jsonrpc":"2.0","id":6,"result":{}}"#) == nil)
    }

    // MARK: Agents

    private func request(_ provider: Provider, presentsFiles: Bool = true, allowsMCP: Bool = true) -> ChatRequest {
        ChatRequest(
            provider: provider,
            settings: ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true, allowsMCP: allowsMCP),
            systemPrompt: "Be brief.",
            messages: [ChatMessage(role: .user, text: "Hi")],
            workspace: URL(fileURLWithPath: "/tmp/ws"),
            presentsFiles: presentsFiles
        )
    }

    @Test func claudeCodeGetsTheServerAndLeaveToUseIt() throws {
        let executable = try #require(Bundle.main.executableURL).path
        let arguments = try CommandLineClient.invocation(for: request(.claudeCode)).arguments
        #expect(arguments.contains("--strict-mcp-config"))
        let config = try #require(arguments.firstIndex(of: "--mcp-config"))
        let json = try #require(JSONSerialization.jsonObject(with: Data(arguments[config + 1].utf8)) as? [String: Any])
        let server = try #require((json["mcpServers"] as? [String: Any])?["meraline"] as? [String: Any])
        #expect(server["command"] as? String == executable)
        #expect(server["args"] as? [String] == ["--present-files-server", "/tmp/ws"])
        let allowed = try #require(arguments.firstIndex(of: "--allowedTools"))
        #expect(arguments[(allowed + 1)...].contains("mcp__meraline__present_files"))
        let prompt = try #require(arguments.firstIndex(of: "--system-prompt"))
        #expect(arguments[prompt + 1] == "Be brief.\n\n" + PresentFilesServer.instructions)

        let without = try CommandLineClient.invocation(for: request(.claudeCode, presentsFiles: false)).arguments
        #expect(!without.contains("--mcp-config"))
        #expect(!without.contains { $0.contains("meraline") })
        #expect(without[try #require(without.firstIndex(of: "--system-prompt")) + 1] == "Be brief.")
    }

    @Test func codexGetsTheServerEvenWithTheOthersOff() throws {
        let executable = try #require(Bundle.main.executableURL).path
        let invocation = try CommandLineClient.invocation(for: request(.codex, allowsMCP: false))
        let arguments = invocation.arguments
        let command = try #require(arguments.firstIndex(of: "mcp_servers.meraline.command=\"\(executable)\""))
        #expect(try #require(arguments.firstIndex(of: "mcp_servers={}")) < command)
        #expect(arguments.contains(#"mcp_servers.meraline.args=["--present-files-server", "/tmp/ws"]"#))
        #expect(CommandLineClient.systemPrompt(for: request(.codex, allowsMCP: false)).contains(PresentFilesServer.instructions))
        #expect(!(try CommandLineClient.invocation(for: request(.codex, presentsFiles: false))).arguments.contains { $0.contains("meraline") })
    }

    @Test func openCodeGetsTheServerInItsInlineConfig() throws {
        let executable = try #require(Bundle.main.executableURL).path
        let invocation = try CommandLineClient.invocation(for: request(.opencode))
        let config = try #require(invocation.environment["OPENCODE_CONFIG_CONTENT"])
        let json = try #require(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        let server = try #require((json["mcp"] as? [String: Any])?["meraline"] as? [String: Any])
        #expect(server["type"] as? String == "local")
        #expect(server["command"] as? [String] == [executable, "--present-files-server", "/tmp/ws"])
        #expect(invocation.arguments.last?.contains(PresentFilesServer.instructions) == true)
        #expect(try CommandLineClient.invocation(for: request(.opencode, presentsFiles: false)).environment.isEmpty)
    }

    @Test func tomlStringsAreEscaped() {
        #expect(CommandLineClient.tomlString(#"/a "b" \c"#) == #""/a \"b\" \\c""#)
        #expect(CommandLineClient.tomlString("a\nb\u{1}") == #""a\nb\u0001""#)
        #expect(CommandLineClient.tomlKey("my server") == #""my server""#)
    }

    @Test func eachAgentsCallIsRead() throws {
        let claude = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"mcp__meraline__present_files","input":{"filepaths":["report.md","out/chart.csv"]}}]}}"#
        #expect(try StreamDecoder.decode(claude, from: .claudeCode) == .presented(["report.md", "out/chart.csv"]))
        let start = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t","name":"mcp__meraline__present_files","input":{}}}}"#
        #expect(try StreamDecoder.decode(start, from: .claudeCode) == .activity(.presenting))

        let started = #"{"method":"item/started","params":{"item":{"type":"mcpToolCall","id":"c","server":"meraline","tool":"present_files","status":"inProgress","arguments":{"filepaths":["report.md"]},"result":null,"error":null},"threadId":"t","turnId":"u"}}"#
        #expect(try StreamDecoder.decode(started, from: .codex) == .activity(.presenting))
        let completed = #"{"method":"item/completed","params":{"item":{"type":"mcpToolCall","id":"c","server":"meraline","tool":"present_files","status":"completed","arguments":{"filepaths":["report.md"]},"result":{"content":[{"type":"text","text":"Handed"}]},"error":null},"threadId":"t","turnId":"u"}}"#
        #expect(try StreamDecoder.decode(completed, from: .codex) == .presented(["report.md"]))
        let failed = completed.replacingOccurrences(of: #""status":"completed""#, with: #""status":"failed""#)
        #expect(try StreamDecoder.decode(failed, from: .codex) == .ignored)

        let opencode = #"{"type":"tool_use","part":{"type":"tool","tool":"meraline_present_files","callID":"c","state":{"status":"completed","input":{"filepaths":["/tmp/ws/report.md"]},"output":"Handed"}}}"#
        #expect(try StreamDecoder.decode(opencode, from: .opencode) == .presented(["/tmp/ws/report.md"]))
        let running = opencode.replacingOccurrences(of: #""status":"completed""#, with: #""status":"running""#)
        #expect(try StreamDecoder.decode(running, from: .opencode) == .activity(.presenting))

        // An input that is odd in one way still says what it can.
        let odd = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"WebSearch","input":{"query":7,"url":"https://example.com"}}]}}"#
        #expect(try StreamDecoder.decode(odd, from: .claudeCode) == .activity(.searching(nil)))
    }

    // MARK: The chat

    /// A session asking Claude Code, whose answer writes report.md into the chat's workspace and hands it over,
    /// twice and with a file that isn't there.
    private func handingSession() -> (ChatSession, Requests) {
        let preferences = GameTestSupport.preferences(withProvider: false)
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.mode = .agent
        let requests = Requests()
        let session = ChatSession(preferences: preferences, workspaceRoot: root) { request in
            requests.all.append(request)
            let isFirst = requests.all.count == 1
            return AsyncThrowingStream { continuation in
                if isFirst, let workspace = request.workspace {
                    try? Data("# Report".utf8).write(to: workspace.appending(path: "report.md"))
                    continuation.yield(.activity(.presenting))
                    continuation.yield(.presented(["report.md", "missing.pdf"]))
                    continuation.yield(.presented([workspace.path + "/report.md"]))
                }
                continuation.yield(.text("Here it is."))
                continuation.finish()
            }
        }
        return (session, requests)
    }

    @Test func handedOverFilesJoinTheAnswer() async throws {
        let (session, requests) = handingSession()
        defer { ChatWorkspace.removeAll(in: root) }
        await GameTestSupport.play("Write me a report", in: session)
        let turn = try #require(session.turns.last)
        #expect(turn.presentedFiles.map(\.path) == ["report.md"])
        #expect(turn.tools.isEmpty)
        #expect(session.lastPresentedFiles == turn.presentedFiles)
        #expect(requests.all.last?.presentsFiles == true)
        #expect(ChatSession.markdown(for: session.turns)?.contains("Here it is.\n\n_report.md handed over_") == true)

        // A follow-up tells the agent which files it handed over.
        let next = session.makeRequest(asking: "Make it shorter", images: [], of: .claudeCode)
        #expect(next.messages.map(\.presentedFiles) == [[], ["report.md"], []])
        #expect(CommandLineClient.transcript(of: next.messages).contains("Here it is.\n\nHanded to the person with present_files:\n- report.md"))

        // A rewrite tells the answer again and keeps its files.
        session.rewrite(.shorter)
        await GameTestSupport.settle(session)
        #expect(session.turns.last?.presentedFiles.map(\.path) == ["report.md"])
    }

    @Test func handedOverFilesHaveTheirOwnActions() async throws {
        let (session, _) = handingSession()
        defer { ChatWorkspace.removeAll(in: root) }
        await GameTestSupport.play("Write me a report", in: session)
        let file = try #require(session.lastPresentedFiles.first)
        let context = PanelContext(session: session, preferences: GameTestSupport.preferences(), layout: PanelLayout(), openSettings: { _ in })
        let actions = try #require(context.chatMenu?.actions)
        let open = try #require(actions.first { $0.id == "openFile.\(file.id)" })
        #expect(open.title == "Open report.md")
        #expect(open.shortcut == .command("o"))
        #expect(actions.first { $0.id == "saveFiles" }?.shortcut == .command("s"))
        #expect(actions.first { $0.id == "copyFiles" }?.title == "Copy report.md")
        #expect(actions.first { $0.id == "showFiles" }?.title == "Show report.md in Finder")

        // Once the file has gone, there is nothing to do with it.
        try FileManager.default.removeItem(at: file.url)
        #expect(context.chatMenu?.actions.contains { $0.id == "saveFiles" } == false)
    }

    @Test func gamesDoNotHandOverFiles() async {
        let (session, requests) = handingSession()
        defer { ChatWorkspace.removeAll(in: root) }
        session.startGame(.rhymeDuel)
        await GameTestSupport.settle(session)
        #expect(requests.all.last?.presentsFiles == false)
    }

    // MARK: For real

    /// Runs each installed agent for real with Meraline's own server, from this test host's executable, and a
    /// file waiting in the workspace: the agent hands it over.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil), .timeLimit(.minutes(3)))
    func installedAgentsHandOverAFile() async throws {
        let models: [Provider: String] = [.claudeCode: "haiku", .codex: "", .opencode: "opencode/big-pickle"]
        for provider in Provider.commandLineTools where CommandLineClient.resolve(provider.defaultBaseURL) != nil {
            let workspace = try ChatWorkspace.make(in: root)
            defer { workspace.remove() }
            try Data("# Report\n\nAll good.\n".utf8).write(to: workspace.url.appending(path: "report.md"))
            let request = ChatRequest(
                provider: provider,
                settings: ProviderSettings(model: models[provider]!, baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: true, allowsWebSearch: false, effort: .low, allowsMCP: false),
                systemPrompt: "Be brief.",
                messages: [ChatMessage(role: .user, text: "Give me the file report.md from your working directory.")],
                workspace: workspace.url,
                presentsFiles: true
            )
            var handed: [String] = []
            for try await output in LLMClient.stream(request) {
                if case .presented(let paths) = output { handed += paths }
            }
            let files = PresentedFile.handOver(handed, in: workspace.url).files
            #expect(files.map(\.path) == ["report.md"], "\(provider.name) handed over: \(handed)")
        }
    }
}

/// The requests a session sent, in order.
@MainActor
private final class Requests {
    var all: [ChatRequest] = []
}
