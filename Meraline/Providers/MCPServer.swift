import Foundation

/// An MCP server one of the agents has set up. Meraline learns about them by asking the agent itself
/// (`claude mcp list`, `codex mcp list --json`, `opencode mcp list`) and never edits its configuration;
/// turning a server off in Settings only keeps it out of Meraline's own questions.
nonisolated struct MCPServer: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The agent reached the server when it listed it.
        case connected
        /// The agent lists it without checking it (Codex lists servers without connecting).
        case configured
        /// The agent could not reach it.
        case failed(String?)
        /// The server wants a sign-in first (`codex mcp login`, `opencode mcp auth`).
        case needsSignIn
        /// The agent is waiting for you to approve the server.
        case pendingApproval
        /// Turned off in the agent's own configuration; Meraline leaves that alone.
        case disabledByAgent

        var title: String {
            switch self {
            case .connected: "Connected"
            case .configured: "Set up"
            case .failed(let reason?): "Couldn’t connect: \(reason)"
            case .failed: "Couldn’t connect"
            case .needsSignIn: "Not signed in"
            case .pendingApproval: "Waiting for approval"
            case .disabledByAgent: "Turned off"
            }
        }

        /// Whether Meraline may offer the server to the agent at all.
        var isUsable: Bool { self != .disabledByAgent }
    }

    let name: String
    /// The command or URL behind the server, for display only.
    var target = ""
    var status = Status.configured

    var id: String { name }

    /// How Claude Code spells a server inside a tool name, `mcp__<server>__<tool>`: anything but letters,
    /// digits, `-`, and `_` becomes `_`, so "claude.ai Claude Docs" is `claude_ai_Claude_Docs`.
    static func toolPrefix(for name: String) -> String {
        String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
    }

    /// A tool name the way a person would say it: `search_knowledge` reads "search knowledge".
    static func humanized(_ tool: String) -> String {
        tool.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmed
    }
}

/// Asks an agent for its MCP servers and reads the answer. The parsers are pure, so they are tested
/// against captured output; `list(for:command:)` runs the agent.
nonisolated enum MCPServerDiscovery {
    static let timeout: Duration = .seconds(60)

    static func arguments(for provider: Provider) -> [String] {
        switch provider {
        case .codex: ["mcp", "list", "--json"]
        default: ["mcp", "list"]
        }
    }

    static func list(for provider: Provider, command: String) async throws -> [MCPServer] {
        guard provider.supportsMCP else { return [] }
        guard let executable = CommandLineClient.resolve(command) else {
            throw LLMError.commandNotFound(provider, command.trimmed)
        }
        Log.commandLine.info("Listing MCP servers with \(executable.path) for \(provider.name)")
        let output = try await CommandLineClient.output(of: executable, arguments: arguments(for: provider), timeout: timeout)
        return try parse(output, from: provider)
    }

    static func parse(_ output: String, from provider: Provider) throws -> [MCPServer] {
        switch provider {
        case .claudeCode: parseClaudeCode(output)
        case .codex: try parseCodex(Data(output.utf8))
        case .opencode: parseOpenCode(output)
        default: []
        }
    }

    /// `claude mcp list` prints one line per server: `name: command or URL - ✔ Connected`. The header
    /// line ("Checking MCP server health…") and blank lines are skipped.
    static func parseClaudeCode(_ text: String) -> [MCPServer] {
        stripped(text).components(separatedBy: .newlines).compactMap { line in
            let line = line.trimmed
            guard let separator = line.range(of: " - ", options: .backwards) else { return nil }
            let head = line[..<separator.lowerBound]
            let tail = line[separator.upperBound...].trimmed
            guard let colon = head.range(of: ": ") ?? (head.hasSuffix(":") ? head.range(of: ":", options: .backwards) : nil) else {
                return nil
            }
            let name = head[..<colon.lowerBound].trimmed
            guard !name.isEmpty else { return nil }
            return MCPServer(name: name, target: head[colon.upperBound...].trimmed, status: claudeStatus(tail))
        }
    }

    private static func claudeStatus(_ text: String) -> MCPServer.Status {
        let lowered = text.lowercased()
        if lowered.contains("connected") && !lowered.contains("not connected") && !lowered.contains("disconnected") { return .connected }
        if lowered.contains("pending") || lowered.contains("approval") { return .pendingApproval }
        if lowered.contains("needs authentication") || lowered.contains("auth") || lowered.contains("sign in") { return .needsSignIn }
        if lowered.contains("disabled") { return .disabledByAgent }
        if lowered.contains("failed") || lowered.contains("error") { return .failed(nil) }
        return .configured
    }

    /// `codex mcp list --json` is an array of servers with `name`, `enabled`, a `transport` (`url` or
    /// `command` plus `args`), and `auth_status`.
    static func parseCodex(_ data: Data) throws -> [MCPServer] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([CodexServer].self, from: data).map { server in
            let target = server.transport?.url
                ?? ([server.transport?.command].compactMap { $0 } + (server.transport?.args ?? [])).joined(separator: " ")
            let status: MCPServer.Status
            if server.enabled == false {
                status = .disabledByAgent
            } else if server.authStatus == "not_logged_in" {
                status = .needsSignIn
            } else {
                status = .configured
            }
            return MCPServer(name: server.name, target: target, status: status)
        }
    }

    /// `opencode mcp list` draws a tree: a `✓ name connected`, `✗ name failed`, or `○ name disabled` line,
    /// then an indented line with the command or URL and, after a failure, the reason.
    static func parseOpenCode(_ text: String) -> [MCPServer] {
        var servers: [MCPServer] = []
        for raw in stripped(text).components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "│┌└●◇◆├─┐┘ \t"))
            guard !line.isEmpty else { continue }
            if let marker = line.first, "✓✔✗✘○◌•".contains(marker) {
                let rest = line.dropFirst().trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard let name = rest.first else { continue }
                let word = rest.dropFirst().joined(separator: " ").lowercased()
                let status: MCPServer.Status
                if word.contains("connected") {
                    status = .connected
                } else if word.contains("disabled") {
                    status = .disabledByAgent
                } else if word.contains("auth") || word.contains("login") {
                    status = .needsSignIn
                } else if word.contains("failed") || word.contains("error") {
                    status = .failed(nil)
                } else {
                    status = .configured
                }
                servers.append(MCPServer(name: name, status: status))
            } else if var last = servers.popLast() {
                if last.target.isEmpty && !line.hasPrefix("MCP Servers") && !line.hasSuffix("server(s)") {
                    if case .failed(nil) = last.status, !line.hasPrefix("/") && !line.contains("://") {
                        last.status = .failed(line)
                    } else {
                        last.target = line
                    }
                }
                servers.append(last)
            }
        }
        return servers
    }

    /// Terminal colors, which OpenCode prints even when no one is watching.
    private static func stripped(_ text: String) -> String {
        text.replacing(/\u{1B}\[[0-9;?]*[A-Za-z]/, with: "")
    }

    private struct CodexServer: Decodable {
        let name: String
        let enabled: Bool?
        let transport: Transport?
        let authStatus: String?

        struct Transport: Decodable {
            let type: String?
            let url: String?
            let command: String?
            let args: [String]?
        }
    }
}

nonisolated extension Substring {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
