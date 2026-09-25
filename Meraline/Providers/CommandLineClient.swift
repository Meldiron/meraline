import Foundation

nonisolated struct CommandInvocation: Equatable, Sendable {
    var executable: URL
    var arguments: [String]
    var input: Data?
    var files: [String: Data] = [:]
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
        let model = request.settings.model.trimmed
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
                "--strict-mcp-config",
                "--system-prompt", request.systemPrompt
            ]
            if !model.isEmpty { arguments += ["--model", model] }
            if request.settings.effort != .automatic { arguments += ["--effort", request.settings.effort.rawValue] }
            if request.settings.allowsWebSearch {
                arguments += ["--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch", "WebFetch"]
            } else {
                arguments += ["--tools", ""]
            }
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
            var arguments = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only"]
            if !model.isEmpty { arguments += ["--model", model] }
            if request.settings.effort != .automatic {
                arguments += ["--config", "model_reasoning_effort=\"\(request.settings.effort.rawValue)\""]
            }
            for name in files.keys.sorted() { arguments += ["--image", name] }
            arguments.append("-")
            let prompt = prompt(for: request)
            return CommandInvocation(executable: executable, arguments: arguments, input: Data(prompt.utf8), files: files)

        case .opencode:
            let files = attachmentFiles(for: images)
            var arguments = ["run", "--format", "json"]
            if !model.isEmpty { arguments += ["--model", model] }
            if request.settings.effort != .automatic { arguments += ["--variant", request.settings.effort.rawValue] }
            for name in files.keys.sorted() { arguments += ["--file", name] }
            arguments += ["--", prompt(for: request)]
            return CommandInvocation(executable: executable, arguments: arguments, files: files)

        default:
            preconditionFailure("\(request.provider) is not a command-line tool")
        }
    }

    static func transcript(of messages: [ChatMessage]) -> String {
        guard messages.count > 1 else { return messages.last?.text ?? "" }
        let history = messages.dropLast().map { message in
            let speaker = message.role == .user ? "User" : "Assistant"
            return "\(speaker): \(message.text)"
        }.joined(separator: "\n\n")
        return """
        <conversation>
        \(history)
        </conversation>

        \(messages.last?.text ?? "")
        """
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

    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let task = Task {
                let directory = FileManager.default.temporaryDirectory.appending(path: "Meraline-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: directory) }
                do {
                    let invocation = try invocation(for: request)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for (name, data) in invocation.files {
                        try data.write(to: directory.appending(path: name))
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
                    var environment = ProcessInfo.processInfo.environment
                    environment["PATH"] = ([invocation.executable.deletingLastPathComponent().path] + searchPaths).joined(separator: ":")
                    environment["NO_COLOR"] = "1"
                    process.environment = environment

                    let exit = AsyncStream<Int32> { stream in
                        process.terminationHandler = { stream.yield($0.terminationStatus); stream.finish() }
                    }
                    try process.run()
                    if let data = invocation.input {
                        try input.fileHandleForWriting.write(contentsOf: data)
                        try input.fileHandleForWriting.close()
                    }

                    async let diagnostics = tail(of: errors.fileHandleForReading)
                    var receivedText = false
                    var needsSeparator = false
                    for try await line in output.fileHandleForReading.bytes.lines {
                        switch try StreamDecoder.decode(line, from: request.provider) {
                        case .text(let text):
                            if needsSeparator { continuation.yield(.text("\n\n")) }
                            continuation.yield(.text(text))
                            receivedText = true
                            needsSeparator = request.provider != .claudeCode
                        case .activity(let activity):
                            needsSeparator = false
                            continuation.yield(.activity(activity))
                        case .finished, .ignored:
                            break
                        }
                    }

                    var status: Int32 = 0
                    for await code in exit { status = code }
                    let message = await diagnostics
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
