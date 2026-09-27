import Foundation

/// Meraline's own MCP server, with the one tool an agent hands files to the person with: `present_files`.
///
/// The agent runs it over stdio, as Meraline's own executable started with `--present-files-server <workspace>`,
/// so there is no helper to ship or sign; that process answers the agent and never starts the app. It checks the
/// paths it is given as the panel does (`PresentedFile.handOver`) and tells the agent what it handed over. The
/// panel doesn't hear from it: it reads the same call in the agent's own stream of events and shows the files
/// under the answer. Every chat with an agent gets it, beside the agent's own servers, whatever Settings says
/// about those.
nonisolated enum PresentFilesServer {
    static let flag = "--present-files-server"
    static let name = "meraline"
    static let tool = "present_files"
    /// The tool as Claude Code names it, and as OpenCode does. Codex names the server and the tool apart.
    static let claudeCodeTool = "mcp__\(name)__\(tool)"
    static let openCodeTool = "\(name)_\(tool)"

    /// Whether an agent's name for a tool is this one.
    static func isTool(_ name: String) -> Bool {
        name == claudeCodeTool || name == openCodeTool
    }

    /// Added to the system prompt of a chat with an agent.
    static let instructions = """
    You work in a folder of your own, your working directory. When the person should get a file from you, such as \
    something they asked you to make or a result that is better as a file than as text, save it there and hand it \
    over with the present_files tool, from the meraline MCP server: Meraline shows it under your answer, where they \
    can open, copy, or save it. Hand over only finished files, not scratch files or files you only read, and don't \
    paste a handed-over file's contents into your answer.
    """

    static let toolDescription = """
    Hands files to the person you work for. Meraline shows each one under your answer as a card they can open in \
    its app, show in Finder, copy, save to Downloads, or drag out. Use it for every finished file they should get: \
    one they asked for, or a result that is better as a file than as text. Save the file in the working directory \
    first. Don't use it for scratch files or files you only read, and don't repeat a handed-over file's contents in \
    your answer.
    """

    /// How an agent starts the server.
    struct Command: Equatable, Sendable {
        let executable: URL
        let arguments: [String]
    }

    /// How an agent starts the server for a chat's workspace: Meraline's executable, or nil when there is none.
    static func command(for workspace: URL, executable: URL? = Bundle.main.executableURL) -> Command? {
        executable.map { Command(executable: $0, arguments: [flag, workspace.path]) }
    }

    /// The workspace to serve, when Meraline was started as the server.
    static func workspace(in arguments: [String]) -> URL? {
        guard arguments.count == 3, arguments[1] == flag, !arguments[2].isEmpty else { return nil }
        return URL(fileURLWithPath: arguments[2], isDirectory: true)
    }

    /// Answers the agent, one line of JSON-RPC at a time, until it closes stdin.
    static func serve(in workspace: URL) {
        Log.commandLine.info("Serving \(tool) to an agent")
        while let line = readLine() {
            guard var reply = reply(to: Data(line.utf8), in: workspace) else { continue }
            reply.append(0x0A)
            do {
                try FileHandle.standardOutput.write(contentsOf: reply)
            } catch {
                return
            }
        }
    }

    /// The versions of MCP the server speaks; it answers in the agent's own when it knows it, else the newest.
    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    /// The reply to one message from the agent, or nil for a notification, which gets none.
    static func reply(to message: Data, in workspace: URL) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let method = object["method"] as? String, let id = object["id"], !(id is NSNull) else { return nil }
        let params = object["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            result = [
                "protocolVersion": protocolVersions.contains(asked) ? asked : protocolVersions[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": name, "title": "Meraline", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"]
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": [toolDefinition]]
        case "tools/call":
            guard params["name"] as? String == tool else {
                return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool"]])
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            result = call(paths: arguments["filepaths"] as? [String] ?? [], in: workspace)
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
        }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    /// What `present_files` says back: what it handed over, and what it couldn't, which makes it an error for the
    /// agent to fix.
    private static func call(paths: [String], in workspace: URL) -> [String: Any] {
        let (files, problems) = PresentedFile.handOver(paths, in: workspace)
        var lines: [String] = []
        if !files.isEmpty {
            lines.append("Handed to the person: \(files.map(\.path).joined(separator: ", ")). Meraline shows \(files.count == 1 ? "it" : "them") under your answer.")
            Log.commandLine.info("Handed \(files.count) file(s) to the person")
        }
        if !files.isEmpty && !problems.isEmpty { lines.append("Couldn’t hand over the rest:") }
        lines += problems
        return ["content": [["type": "text", "text": lines.joined(separator: "\n")]], "isError": !problems.isEmpty]
    }

    static var toolDefinition: [String: Any] {
        [
            "name": tool,
            "title": "Present files",
            "description": toolDescription,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "filepaths": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Paths of the files or folders to hand over, relative to the working directory or absolute inside it. At most \(PresentedFile.limit)."
                    ]
                ],
                "required": ["filepaths"]
            ],
            // Nothing changes and nothing leaves the Mac, so Codex, which can't ask in its exec mode, runs it.
            "annotations": ["readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
        ]
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
