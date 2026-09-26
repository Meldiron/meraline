import Foundation

nonisolated struct CommandInvocation: Equatable, Sendable {
    var executable: URL
    var arguments: [String]
    var input: Data?
    var files: [String: Data] = [:]
    /// Variables added to the agent's environment, on top of Meraline's own and `PATH`.
    var environment: [String: String] = [:]
}

nonisolated enum CommandLineClient {
    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let common = [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.opencode/bin",
            "\(home)/.bun/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        var seen = Set<String>()
        return (common + inherited).filter { seen.insert($0).inserted }
    }

    static func resolve(_ command: String) -> URL? {
        let command = (command.trimmed as NSString).expandingTildeInPath
        guard !command.isEmpty else { return nil }
        if command.contains("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? URL(fileURLWithPath: command) : nil
        }
        return searchPaths
            .map { URL(fileURLWithPath: $0).appending(path: command) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func invocation(for request: ChatRequest) throws -> CommandInvocation {
        guard let executable = resolve(request.settings.baseURL) else {
            throw LLMError.commandNotFound(request.provider, request.settings.baseURL.trimmed)
        }
        let settings = request.settings
        let model = settings.model.trimmed
        let images = request.messages.flatMap(\.images)

        switch request.provider {
        case .claudeCode:
            var arguments = [
                "--print",
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--no-session-persistence",
                "--system-prompt", request.systemPrompt
            ]
            if !model.isEmpty { arguments += ["--model", model] }
            if settings.effort != .automatic { arguments += ["--effort", settings.effort.rawValue] }
            // Built-in tools: the web when allowed, the file tools for the chat's workspace, and
            // AskUserQuestion. Anything not allowed by name below is asked about over stdin and stdout
            // (`--permission-prompt-tool stdio`), which is how a write to the workspace or a question of
            // claude's own reaches the panel. MCP servers come from claude's own configuration; an allow
            // rule must name its server (`mcp__*` is ignored), so the servers listed last time are named
            // one by one. A server turned off in Settings is denied by name, which also hides its tools.
            // With no server to name, `--strict-mcp-config` keeps claude from starting any.
            var tools = Self.claudeCodeWorkspaceTools
            var allowed: [String] = []
            if settings.allowsWebSearch {
                tools = ["WebSearch", "WebFetch"] + tools
                allowed += ["WebSearch", "WebFetch"]
            }
            arguments += ["--tools", tools.joined(separator: ","), "--permission-prompt-tool", "stdio"]
            let servers = settings.allowedMCPServers
            if servers.isEmpty {
                arguments.append("--strict-mcp-config")
            } else {
                allowed += servers.map { "mcp__\(MCPServer.toolPrefix(for: $0))" }
            }
            if !allowed.isEmpty { arguments += ["--allowedTools"] + allowed }
            let denied = servers.isEmpty ? [] : settings.knownMCPServers.filter { settings.disabledMCPServers.contains($0) }
            if !denied.isEmpty { arguments += ["--disallowedTools"] + denied.map { "mcp__\(MCPServer.toolPrefix(for: $0))" } }
            var content: [[String: Any]] = images.map { image in
                ["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.base64]]
            }
            content.append(["type": "text", "text": transcript(of: request.messages)])
            let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
            var input = try JSONSerialization.data(withJSONObject: line)
            input.append(0x0A)
            return CommandInvocation(executable: executable, arguments: arguments, input: input)

        case .codex:
            let files = attachmentFiles(for: images)
            // Commands may write inside the chat's workspace (and the temporary folder) and nowhere
            // else; the sandbox keeps them off the network. Codex's exec mode cannot ask for approval,
            // so anything beyond that fails on its own.
            var arguments = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "workspace-write"]
            if !model.isEmpty { arguments += ["--model", model] }
            if settings.effort != .automatic {
                arguments += ["--config", "model_reasoning_effort=\"\(settings.effort.rawValue)\""]
            }
            // Codex's search modes are disabled, cached, indexed, and live. Live is the only one that
            // asks the web for anything newer than the model's index.
            arguments += ["--config", "web_search=\"\(settings.allowsWebSearch ? "live" : "disabled")\""]
            // Codex loads the MCP servers in its config.toml on its own. These overrides turn off the ones
            // turned off in Settings, or all of them, for this run only; the file is never touched.
            if !settings.allowsMCP {
                arguments += ["--config", "mcp_servers={}"]
            } else {
                for name in settings.disabledMCPServers.sorted() {
                    arguments += ["--config", "mcp_servers.\(tomlKey(name)).enabled=false"]
                }
            }
            for name in files.keys.sorted() { arguments += ["--image", name] }
            arguments.append("-")
            let prompt = prompt(for: request)
            return CommandInvocation(executable: executable, arguments: arguments, input: Data(prompt.utf8), files: files)

        case .opencode:
            let files = attachmentFiles(for: images)
            var arguments = ["run", "--format", "json"]
            if !model.isEmpty { arguments += ["--model", model] }
            if settings.effort != .automatic { arguments += ["--variant", settings.effort.rawValue] }
            for name in files.keys.sorted() { arguments += ["--file", name] }
            arguments += ["--", prompt(for: request)]
            // OpenCode merges OPENCODE_CONFIG_CONTENT over its configuration files, so a server can be
            // turned off for this run alone while its definition stays where it is.
            var off = settings.disabledMCPServers
            if !settings.allowsMCP { off.formUnion(settings.knownMCPServers) }
            var environment: [String: String] = [:]
            if !off.isEmpty { environment["OPENCODE_CONFIG_CONTENT"] = try openCodeOverrides(disabling: off.sorted()) }
            return CommandInvocation(executable: executable, arguments: arguments, files: files, environment: environment)

        default:
            preconditionFailure("\(request.provider) is not a command-line tool")
        }
    }

    /// Claude Code's built-in tools for the chat's workspace. Reading inside it needs no leave; a write,
    /// an edit, a command claude doesn't judge read-only, or a skill is asked about, and AskUserQuestion
    /// is how claude asks something of its own.
    static let claudeCodeWorkspaceTools = ["Read", "Write", "Edit", "Glob", "Grep", "Bash", "Skill", "AskUserQuestion"]

    /// A TOML key for a server name: bare when it can be, quoted otherwise.
    static func tomlKey(_ name: String) -> String {
        let bare = !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        if bare { return name }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// The inline OpenCode configuration that turns the named servers off: `{"mcp":{"name":{"enabled":false}}}`.
    static func openCodeOverrides(disabling servers: [String]) throws -> String {
        let mcp = Dictionary(uniqueKeysWithValues: servers.map { ($0, ["enabled": false]) })
        let data = try JSONSerialization.data(withJSONObject: ["mcp": mcp], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func transcript(of messages: [ChatMessage]) -> String {
        guard messages.count > 1 else { return messages.last.map(text(of:)) ?? "" }
        let history = messages.dropLast().map { message in
            let speaker = message.role == .user ? "User" : "Assistant"
            return "\(speaker): \(text(of: message))"
        }.joined(separator: "\n\n")
        return """
        <conversation>
        \(history)
        </conversation>

        \(messages.last.map(text(of:)) ?? "")
        """
    }

    /// A message's text, followed by the names of the files and folders attached to it, which the agent finds
    /// copied into its working directory. A folder's name ends in a slash.
    private static func text(of message: ChatMessage) -> String {
        guard !message.files.isEmpty else { return message.text }
        let names = message.files.map { "- \($0.name)\($0.isFolder ? "/" : "")" }
        let note = (["Attached, copied into the working directory:"] + names).joined(separator: "\n")
        return message.text.isEmpty ? note : "\(message.text)\n\n\(note)"
    }

    private static func prompt(for request: ChatRequest) -> String {
        """
        <instructions>
        \(request.systemPrompt)
        </instructions>

        \(transcript(of: request.messages))
        """
    }

    private static func attachmentFiles(for images: [ImageAttachment]) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: images.enumerated().map { index, image in
            ("image-\(index + 1).\(image.mediaType == "image/png" ? "png" : "jpg")", image.data)
        })
    }

    /// Meraline's own environment with the agent's folder and the usual install folders on `PATH`.
    static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([executable.deletingLastPathComponent().path] + searchPaths).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// Runs the agent in the chat's workspace, or in a folder for this run alone when the request has
    /// none. Attached images are written there for the run and removed afterwards; the workspace itself
    /// stays, since it is the chat's. The files and folders attached to the question are copied in and stay
    /// with it, so a follow-up can come back to them.
    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let task = Task {
                let directory = request.workspace ?? FileManager.default.temporaryDirectory.appending(path: "Meraline-\(UUID().uuidString)")
                var written: [URL] = []
                defer {
                    if request.workspace == nil {
                        try? FileManager.default.removeItem(at: directory)
                    } else {
                        for file in written { try? FileManager.default.removeItem(at: file) }
                    }
                }
                do {
                    let invocation = try invocation(for: request)
                    let servers = request.settings.allowedMCPServers.count
                    Log.commandLine.info("Running \(invocation.executable.path) for \(request.provider.name)\(servers > 0 ? " with \(servers) MCP server(s)" : "")\(request.workspace == nil ? "" : " in the chat's workspace")")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    if let files = request.messages.last?.files, !files.isEmpty {
                        // A folder can take a few seconds; the panel says so rather than murmur.
                        let folder = files.first(where: \.isFolder)
                        if let folder { continuation.yield(.activity(.copying(folder.name))) }
                        try await FileAttachment.copy(files, into: directory)
                        if folder != nil { continuation.yield(.activity(.thinking)) }
                        Log.commandLine.info("Copied \(files.count) attachment(s) in for \(request.provider.name)")
                    }
                    for (name, data) in invocation.files {
                        let file = directory.appending(path: name)
                        try data.write(to: file)
                        written.append(file)
                    }

                    let output = Pipe()
                    let errors = Pipe()
                    let input = Pipe()
                    process.executableURL = invocation.executable
                    process.arguments = invocation.arguments
                    process.currentDirectoryURL = directory
                    process.standardOutput = output
                    process.standardError = errors
                    process.standardInput = invocation.input == nil ? FileHandle.nullDevice : input
                    process.environment = environment(for: invocation.executable).merging(invocation.environment) { $1 }

                    let exit = AsyncStream<Int32> { stream in
                        process.terminationHandler = { stream.yield($0.terminationStatus); stream.finish() }
                    }
                    try process.run()
                    // Claude Code takes answers to its prompts on stdin, so its stdin stays open until
                    // the result; the others read their prompt to the end of stdin first.
                    let writer = input.fileHandleForWriting
                    let answersOnInput = request.provider == .claudeCode
                    if let data = invocation.input {
                        try writer.write(contentsOf: data)
                        if !answersOnInput { try writer.close() }
                    }

                    async let diagnostics = tail(of: errors.fileHandleForReading)
                    var receivedText = false
                    var needsSeparator = false
                    for try await line in lines(of: output.fileHandleForReading) {
                        switch try StreamDecoder.decode(line, from: request.provider, knownServers: request.settings.knownMCPServers) {
                        case .text(let text):
                            if needsSeparator { continuation.yield(.text("\n\n")) }
                            continuation.yield(.text(text))
                            receivedText = true
                            needsSeparator = request.provider != .claudeCode
                        case .activity(let activity):
                            needsSeparator = false
                            continuation.yield(.activity(activity))
                        case .prompt(let prompt):
                            needsSeparator = false
                            var responder: AgentPromptResponder?
                            if prompt.isPending && answersOnInput {
                                responder = AgentPromptResponder { answer in
                                    do {
                                        try writer.write(contentsOf: try prompt.claudeCodeResponse(answer))
                                        Log.commandLine.info("Answer sent to \(request.provider.name)")
                                    } catch {
                                        Log.commandLine.error("Couldn’t answer \(request.provider.name): \(error.localizedDescription)")
                                    }
                                }
                            }
                            continuation.yield(.prompt(prompt, responder))
                        case .finished:
                            if answersOnInput { try? writer.close() }
                        case .ignored:
                            break
                        }
                    }
                    if answersOnInput { try? writer.close() }

                    var status: Int32 = 0
                    for await code in exit { status = code }
                    let message = await diagnostics
                    if status != 0 {
                        Log.commandLine.error("\(request.provider.name) exited with status \(status)\(receivedText ? " after answering" : "")")
                    }
                    if status != 0 && !receivedText {
                        throw LLMError.provider(message.isEmpty ? "\(request.provider.name) exited with status \(status)." : message)
                    }
                    if !receivedText { throw LLMError.emptyResponse }
                    continuation.finish()
                } catch {
                    if process.isRunning { process.terminate() }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// Runs a command to completion and returns what it printed, for `mcp list` and the like. The
    /// command is stopped after `timeout`, or when the task is cancelled.
    static func output(of executable: URL, arguments: [String], timeout: Duration) async throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        process.environment = environment(for: executable)
        let exit = AsyncStream<Int32> { stream in
            process.terminationHandler = { stream.yield($0.terminationStatus); stream.finish() }
        }
        try process.run()
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }
        return try await withTaskCancellationHandler {
            async let printed = contents(of: output.fileHandleForReading)
            async let diagnostics = tail(of: errors.fileHandleForReading)
            var status: Int32 = 0
            for await code in exit { status = code }
            let text = await printed
            let message = await diagnostics
            guard status == 0 else {
                throw LLMError.provider(message.isEmpty ? "\(executable.lastPathComponent) exited with status \(status)." : message)
            }
            return text
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Each line from a pipe the moment its newline arrives. `FileHandle.bytes.lines` holds lines back
    /// until more bytes come or the pipe closes, which deadlocks an agent that prints a question and
    /// then waits for the answer. Lines are split on bytes, so a character is never cut in two.
    static func lines(of handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            let pending = PendingBytes()
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    if let rest = pending.drain() { continuation.yield(rest) }
                    continuation.finish()
                    return
                }
                for line in pending.append(data) { continuation.yield(line) }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }

    /// The bytes after the last newline, waiting for the rest of their line. The readability handler
    /// that owns it runs one call at a time.
    private final class PendingBytes: @unchecked Sendable {
        private var buffer = Data()

        func append(_ data: Data) -> [String] {
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                var line = buffer[buffer.startIndex..<newline]
                if line.last == 0x0D { line = line.dropLast() }
                lines.append(String(decoding: line, as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }

        func drain() -> String? {
            defer { buffer = Data() }
            return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
        }
    }

    private static func contents(of handle: FileHandle) async -> String {
        var data = Data()
        do {
            for try await byte in handle.bytes { data.append(byte) }
        } catch {}
        return String(decoding: data, as: UTF8.self)
    }

    private static func tail(of handle: FileHandle) async -> String {
        var data = Data()
        do {
            for try await byte in handle.bytes {
                data.append(byte)
                if data.count > 16_384 { data.removeFirst(data.count - 8_192) }
            }
        } catch {}
        return String(decoding: data, as: UTF8.self).trimmed
    }
}
