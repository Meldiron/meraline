import Foundation

/// Claude Code and Codex kept running for a chat, so a follow-up doesn't start them cold, and started ahead of
/// the first question when the shortcut opens the window in Agent mode.
///
/// Each chat's agent lives in its workspace, keyed by the folder, and remembers the conversation in its own
/// memory: Claude Code as one `--input-format stream-json` process that reads each question on stdin, Codex as
/// `codex app-server` with a thread. A follow-up sends only the new question. Anything else, such as Ask Again,
/// a rewrite, or an answer from another provider in between, starts over from Meraline's own transcript: Claude
/// Code in a new process, Codex in a new thread. Nothing is resumed from disk, since neither keeps sessions
/// there (`--no-session-persistence`, ephemeral threads). A request without a workspace, such as Test
/// Connection, gets an agent of its own for one answer.
///
/// At most `limit` agents stay; one idle for `idleLifetime`, or whose chat goes, or Stop, ends its process.
nonisolated final class LiveAgents: @unchecked Sendable {
    static let shared = LiveAgents()

    static let limit = 3
    static let idleLifetime: TimeInterval = 15 * 60

    private let lock = NSLock()
    private var agents: [String: LiveAgent] = [:]
    private var sweeper: Task<Void, Never>?

    /// Whether Claude Code or Codex answers through here.
    static func handles(_ provider: Provider) -> Bool {
        provider == .claudeCode || provider == .codex
    }

    /// An answer from the chat's agent, started if it isn't running or can't follow on.
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let directory = request.workspace ?? FileManager.default.temporaryDirectory.appending(path: "Meraline-\(UUID().uuidString)")
                var agent: LiveAgent?
                defer {
                    if request.workspace == nil { try? FileManager.default.removeItem(at: directory) }
                }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    if let files = request.messages.last?.files, !files.isEmpty {
                        // A folder can take a few seconds; the panel says so rather than murmur.
                        let folder = files.first(where: \.isFolder)
                        if let folder { continuation.yield(.activity(.copying(folder.name))) }
                        try await FileAttachment.copy(files, into: directory)
                        if folder != nil { continuation.yield(.activity(.thinking)) }
                        Log.commandLine.info("Copied \(files.count) attachment(s) in for \(request.provider.name)")
                    }
                    let checkedOut = try checkOut(for: request, in: directory)
                    agent = checkedOut
                    try await checkedOut.answer(request) { continuation.yield($0) }
                    checkIn(checkedOut, keeping: request.workspace != nil)
                    continuation.finish()
                } catch {
                    if let agent { discard(agent) }
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : error)
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    /// Starts the chat's agent for the question to come, unless one that can take it is running already.
    func prewarm(_ request: ChatRequest) {
        guard Self.handles(request.provider), let workspace = request.workspace else { return }
        let agent: LiveAgent
        do {
            let signature = try LiveAgent.signature(for: request)
            let made: LiveAgent? = try lock.withLock {
                if let existing = agents[workspace.path], existing.isBusy || existing.canTake(request, signature: signature) {
                    return nil
                }
                agents.removeValue(forKey: workspace.path)?.end()
                let agent = try LiveAgent.make(for: request, signature: signature, in: workspace)
                agents[workspace.path] = agent
                return agent
            }
            guard let made else { return }
            agent = made
        } catch {
            Log.commandLine.error("Couldn’t start \(request.provider.name) ahead: \(error.localizedDescription)")
            return
        }
        Log.commandLine.info("Starting \(request.provider.name) ahead of the question")
        evictBeyondLimit()
        scheduleSweep()
        let warming = agent.warmUp(for: request)
        Task {
            do {
                try await warming.value
            } catch {
                Log.commandLine.error("\(request.provider.name) didn’t start ahead: \(error.localizedDescription)")
                discard(agent)
            }
        }
    }

    /// The chat's workspace is going: its agent goes with it.
    func end(workspace: URL) {
        let agent = lock.withLock { agents.removeValue(forKey: workspace.path) }
        guard let agent else { return }
        agent.end()
        Log.commandLine.info("\(agent.provider.name) ended with its chat")
    }

    /// Ends every agent, at quit.
    func endAll() {
        let all = lock.withLock {
            defer { agents = [:] }
            return Array(agents.values)
        }
        for agent in all { agent.end() }
    }

    /// How many agents are running, for tests and diagnostics.
    var count: Int { lock.withLock { agents.count } }

    // MARK: Checking agents out and in

    /// The chat's agent, when it can take the question; otherwise a new one in its place. It is busy until
    /// checked in or discarded.
    private func checkOut(for request: ChatRequest, in directory: URL) throws -> LiveAgent {
        let signature = try LiveAgent.signature(for: request)
        let key = directory.path
        let agent: LiveAgent = try lock.withLock {
            if request.workspace != nil, let existing = agents[key] {
                if !existing.isBusy && existing.canTake(request, signature: signature) {
                    existing.isBusy = true
                    return existing
                }
                agents.removeValue(forKey: key)
                existing.end()
            }
            let agent = try LiveAgent.make(for: request, signature: signature, in: directory)
            agent.isBusy = true
            if request.workspace != nil { agents[key] = agent }
            return agent
        }
        evictBeyondLimit()
        scheduleSweep()
        return agent
    }

    private func checkIn(_ agent: LiveAgent, keeping: Bool) {
        agent.isBusy = false
        agent.lastUsed = Date()
        if !keeping { agent.end() }
    }

    /// An agent stopped, failed, or went quiet: it ends, and the chat's next question starts a new one.
    private func discard(_ agent: LiveAgent) {
        lock.withLock {
            if let key = agents.first(where: { $0.value === agent })?.key { agents.removeValue(forKey: key) }
        }
        agent.end()
    }

    /// Keeps the `limit` agents used last, ending the others that aren't answering.
    private func evictBeyondLimit() {
        let evicted: [LiveAgent] = lock.withLock {
            let idle = agents.filter { !$0.value.isBusy }.sorted { $0.value.lastUsed < $1.value.lastUsed }
            let excess = max(0, agents.count - Self.limit)
            let keys = idle.prefix(excess).map(\.key)
            return keys.compactMap { agents.removeValue(forKey: $0) }
        }
        for agent in evicted {
            agent.end()
            Log.commandLine.info("\(agent.provider.name) ended to make room for another chat's agent")
        }
    }

    /// Ends agents left idle for `idleLifetime`, checking every minute while any are running.
    private func scheduleSweep() {
        lock.withLock {
            guard sweeper == nil else { return }
            sweeper = Task.detached { [weak self] in
                while let self {
                    try? await Task.sleep(for: .seconds(60))
                    let expired: [LiveAgent] = self.lock.withLock {
                        let cutoff = Date().addingTimeInterval(-Self.idleLifetime)
                        let keys = self.agents.filter { !$0.value.isBusy && $0.value.lastUsed < cutoff }.map(\.key)
                        return keys.compactMap { self.agents.removeValue(forKey: $0) }
                    }
                    for agent in expired {
                        agent.end()
                        Log.commandLine.info("\(agent.provider.name) ended after going unused")
                    }
                    let isEmpty = self.lock.withLock {
                        if self.agents.isEmpty { self.sweeper = nil }
                        return self.agents.isEmpty
                    }
                    if isEmpty { return }
                }
            }
        }
    }
}

/// What an agent kept running has been told and has answered, as the chat will send it back, to tell a
/// follow-up it can take from a question it must start over for.
nonisolated struct AgentMemory: Sendable {
    enum Plan: Equatable {
        /// Nothing told yet: the whole conversation goes in one message.
        case fresh
        /// Only the new question goes.
        case followUp
        /// The conversation isn't the one the agent remembers: start over.
        case startOver
    }

    private(set) var messages: [ChatMessage]?

    func plan(for request: ChatRequest) -> Plan {
        guard let messages else { return .fresh }
        return Self.same(messages, Array(request.messages.dropLast())) ? .followUp : .startOver
    }

    mutating func remember(_ request: ChatRequest, answer: String) {
        messages = request.messages + [ChatMessage(role: .assistant, text: answer)]
    }

    mutating func forget() {
        messages = nil
    }

    /// The same messages, by who said what with which attachments. The files an agent handed over are left out:
    /// the agent knows them already.
    static func same(_ remembered: [ChatMessage], _ sent: [ChatMessage]) -> Bool {
        remembered.count == sent.count && zip(remembered, sent).allSatisfy { mine, theirs in
            mine.role == theirs.role && mine.text == theirs.text && mine.images == theirs.images && mine.files == theirs.files
        }
    }
}

/// An answer as the chat will keep it, from what streams in: text after a tool starts the answer over, as
/// `ChatSession` has it.
nonisolated struct AnswerTracker: Sendable {
    private(set) var answer = ""
    private var startsOver = false

    mutating func note(_ output: StreamOutput) {
        switch output {
        case .activity:
            startsOver = !answer.isEmpty
        case .text(let text):
            answer = startsOver ? text : answer + text
            startsOver = false
        case .prompt, .presented, .usage, .decision, .decisions:
            break
        }
    }
}

/// One chat's agent: Claude Code or Codex, running in the chat's folder.
nonisolated final class LiveAgent: @unchecked Sendable {
    let provider: Provider
    /// The command and its arguments; a question that needs others needs another process.
    let signature: [String]
    let directory: URL

    private let lock = NSLock()
    private var _isBusy = false
    private var _lastUsed = Date()
    fileprivate var memory = AgentMemory()
    private let process: AgentProcess
    private let codex: CodexConnection?
    /// Codex's thread, with the model, instructions, and folder it was started with.
    private var thread: (id: String, signature: [String])?
    /// The thread's running total of tokens, as Codex last reported it, so a turn's share can be worked out.
    private var threadTokens = TokenUsage.zero
    private var warming: Task<Void, Error>?

    var isBusy: Bool {
        get { lock.withLock { _isBusy } }
        set { lock.withLock { _isBusy = newValue } }
    }

    var lastUsed: Date {
        get { lock.withLock { _lastUsed } }
        set { lock.withLock { _lastUsed = newValue } }
    }

    private init(provider: Provider, signature: [String], invocation: CommandInvocation, directory: URL) {
        self.provider = provider
        self.signature = signature
        self.directory = directory
        process = AgentProcess(
            executable: invocation.executable,
            arguments: invocation.arguments,
            environment: CommandLineClient.environment(for: invocation.executable).merging(invocation.environment) { $1 },
            directory: directory
        )
        codex = provider == .codex ? CodexConnection(process: process) : nil
    }

    static func signature(for request: ChatRequest) throws -> [String] {
        let invocation = try CommandLineClient.invocation(for: request)
        let environment = invocation.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return [invocation.executable.path] + invocation.arguments + environment
    }

    /// A new agent for the request, its process started for Claude Code; Codex starts on its first question or
    /// warm-up, which wait for its handshake.
    static func make(for request: ChatRequest, signature: [String], in directory: URL) throws -> LiveAgent {
        let invocation = try CommandLineClient.invocation(for: request)
        let agent = LiveAgent(provider: request.provider, signature: signature, invocation: invocation, directory: directory)
        if request.provider == .claudeCode {
            try agent.process.start()
            Log.commandLine.info("Running \(invocation.executable.path) for Claude Code\(request.workspace == nil ? "" : " in the chat's workspace"), kept for follow-ups")
        }
        return agent
    }

    /// Whether this agent can answer the request: the same command, still running, and a conversation it can
    /// follow on from, or one it can start over in a new thread (Codex).
    func canTake(_ request: ChatRequest, signature: [String]) -> Bool {
        guard provider == request.provider, self.signature == signature, !process.hasEnded else { return false }
        return provider == .codex || memory.plan(for: request) != .startOver
    }

    func end() {
        lock.withLock { warming }?.cancel()
        process.terminate()
    }

    /// Gets the agent ready for the request's first question: Codex shakes hands and opens a thread, which
    /// starts its MCP servers; Claude Code started with its process. The first question waits for it.
    func warmUp(for request: ChatRequest) -> Task<Void, Error> {
        let task = Task { [self] in
            guard let codex else { return }
            try await codex.start()
            try await startThread(for: request)
        }
        lock.withLock { warming = task }
        return task
    }

    /// Answers the request, handing what streams in to `yield`.
    func answer(_ request: ChatRequest, yield: @escaping (StreamOutput) -> Void) async throws {
        let warming = lock.withLock { self.warming }
        _ = try? await warming?.value
        var tracker = AnswerTracker()
        let emit: (StreamOutput) -> Void = { output in
            tracker.note(output)
            yield(output)
        }
        switch provider {
        case .claudeCode: try await answerAsClaudeCode(request, yield: emit)
        case .codex: try await answerAsCodex(request, yield: emit)
        default: preconditionFailure("\(provider) is not kept running")
        }
        guard !Task.isCancelled else { throw CancellationError() }
        memory.remember(request, answer: tracker.answer)
    }

    // MARK: Claude Code

    private func answerAsClaudeCode(_ request: ChatRequest, yield: @escaping (StreamOutput) -> Void) async throws {
        let plan = memory.plan(for: request)
        guard plan != .startOver, let question = request.messages.last else { throw LLMError.emptyResponse }
        if plan == .followUp { Log.commandLine.info("Asking the running Claude Code a follow-up") }
        let messages = plan == .fresh ? request.messages : [question]
        let input = try CommandLineClient.claudeCodeInput(text: CommandLineClient.transcript(of: messages), images: messages.flatMap(\.images))

        let (events, sink) = AsyncStream.makeStream(of: AgentProcess.Event.self)
        process.listen { sink.yield($0) }
        defer {
            process.listen(nil)
            sink.finish()
        }
        try process.send(input)

        let process = process
        var receivedText = false
        loop: for await event in events {
            switch event {
            case .line(let line):
                if let report = StreamDecoder.usage(in: line, from: .claudeCode) {
                    yield(.usage(report.tokens, adds: report.adds))
                }
                switch try StreamDecoder.decode(line, from: .claudeCode, knownServers: request.settings.knownMCPServers) {
                case .text(let text):
                    yield(.text(text))
                    receivedText = true
                case .activity(let activity):
                    yield(.activity(activity))
                case .prompt(let prompt):
                    // claude waits on its stdin for how the ask was settled.
                    let responder = prompt.isPending ? AgentPromptResponder { answer in
                        do {
                            try process.send(try prompt.claudeCodeResponse(answer))
                            Log.commandLine.info("Answer sent to Claude Code")
                        } catch {
                            Log.commandLine.error("Couldn’t answer Claude Code: \(error.localizedDescription)")
                        }
                    } : nil
                    yield(.prompt(prompt, responder))
                case .presented(let paths):
                    yield(.presented(paths))
                case .finished:
                    break loop
                case .ignored:
                    break
                }
            case .ended(let status, let diagnostics):
                Log.commandLine.error("Claude Code exited with status \(status)\(receivedText ? " after answering" : "")")
                guard receivedText else {
                    throw LLMError.provider(diagnostics.isEmpty ? "Claude Code exited with status \(status)." : diagnostics)
                }
                break loop
            }
        }
        guard !Task.isCancelled else { throw CancellationError() }
        if !receivedText { throw LLMError.emptyResponse }
    }

    // MARK: Codex

    private func startThread(for request: ChatRequest) async throws {
        guard let codex else { return }
        var params: [String: Any] = [
            "cwd": directory.path,
            "ephemeral": true,
            "sandbox": "workspace-write",
            "approvalPolicy": "never",
        ]
        let model = request.settings.model.trimmed
        if !model.isEmpty { params["model"] = model }
        let instructions = CommandLineClient.systemPrompt(for: request)
        if !instructions.isEmpty { params["developerInstructions"] = instructions }
        let result = try await codex.request("thread/start", params)
        guard let id = (result["thread"] as? [String: Any])?["id"] as? String else {
            throw LLMError.provider("Codex didn’t open a thread.")
        }
        lock.withLock {
            thread = (id, Self.threadSignature(for: request, in: directory))
            threadTokens = .zero
        }
        memory.forget()
        Log.commandLine.info("Codex opened a thread\(model.isEmpty ? "" : " with \(model)")")
    }

    private static func threadSignature(for request: ChatRequest, in directory: URL) -> [String] {
        [directory.path, request.settings.model.trimmed, CommandLineClient.systemPrompt(for: request)]
    }

    private func answerAsCodex(_ request: ChatRequest, yield: @escaping (StreamOutput) -> Void) async throws {
        guard let codex, let question = request.messages.last else { throw LLMError.emptyResponse }
        try await codex.start()
        var plan = memory.plan(for: request)
        let current = lock.withLock { thread }
        if current == nil || current?.signature != Self.threadSignature(for: request, in: directory) || plan == .startOver {
            try await startThread(for: request)
            plan = .fresh
        } else if plan == .followUp {
            Log.commandLine.info("Asking the running Codex a follow-up")
        }
        guard let threadID = lock.withLock({ thread?.id }) else { throw LLMError.emptyResponse }

        let messages = plan == .fresh ? request.messages : [question]
        // Pictures go in as files in the working folder, for this question only.
        var written: [URL] = []
        defer { for file in written { try? FileManager.default.removeItem(at: file) } }
        var input: [[String: Any]] = [["type": "text", "text": CommandLineClient.transcript(of: messages), "text_elements": []]]
        for (name, data) in CommandLineClient.attachmentFiles(for: messages.flatMap(\.images)).sorted(by: { $0.key < $1.key }) {
            let file = directory.appending(path: name)
            try data.write(to: file)
            written.append(file)
            input.append(["type": "localImage", "path": file.path])
        }

        let (events, sink) = AsyncStream.makeStream(of: AgentProcess.Event.self)
        codex.listen { sink.yield($0) }
        defer {
            codex.listen(nil)
            sink.finish()
        }
        let started = try await codex.request("turn/start", ["threadId": threadID, "input": input])
        guard let turnID = (started["turn"] as? [String: Any])?["id"] as? String else {
            throw LLMError.provider("Codex didn’t start answering.")
        }

        var receivedText = false
        var needsSeparator = false
        loop: for await event in events {
            switch event {
            case .line(let line):
                let envelope = CodexEnvelope(line)
                // Only this question's turn; the thread's other news can wait.
                guard envelope.turnID == nil || envelope.turnID == turnID else { continue }
                if envelope.completesAgentMessage && receivedText { needsSeparator = true }
                // Codex reports the thread's running total; this turn's share is what it grew by.
                if let report = StreamDecoder.usage(in: line, from: .codex) {
                    let grew = lock.withLock {
                        let delta = report.tokens.subtracting(threadTokens)
                        threadTokens = report.tokens
                        return delta
                    }
                    yield(.usage(grew, adds: true))
                }
                switch try StreamDecoder.decode(line, from: .codex) {
                case .text(let text):
                    if needsSeparator { yield(.text("\n\n")) }
                    needsSeparator = false
                    yield(.text(text))
                    receivedText = true
                case .activity(let activity):
                    needsSeparator = false
                    yield(.activity(activity))
                case .prompt(let prompt):
                    yield(.prompt(prompt, nil))
                case .presented(let paths):
                    yield(.presented(paths))
                case .finished:
                    break loop
                case .ignored:
                    break
                }
            case .ended(let status, let diagnostics):
                Log.commandLine.error("Codex exited with status \(status)\(receivedText ? " after answering" : "")")
                guard receivedText else {
                    throw LLMError.provider(diagnostics.isEmpty ? "Codex exited with status \(status)." : diagnostics)
                }
                break loop
            }
        }
        guard !Task.isCancelled else { throw CancellationError() }
        if !receivedText { throw LLMError.emptyResponse }
    }
}

/// The little of an app-server notification the turn needs before decoding it: which turn it is about, and
/// whether it ends one of the agent's messages, after which the next one starts on a new paragraph.
private nonisolated struct CodexEnvelope {
    var turnID: String?
    var completesAgentMessage = false

    init(_ line: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let params = object["params"] as? [String: Any] else { return }
        turnID = params["turnId"] as? String ?? (params["turn"] as? [String: Any])?["id"] as? String
        completesAgentMessage = object["method"] as? String == "item/completed"
            && (params["item"] as? [String: Any])?["type"] as? String == "agentMessage"
    }
}

/// Codex's app server over stdio: JSON-RPC requests with their responses, and its notifications handed to the
/// listener of the moment. A request the server makes of Meraline, which an app server run with approvals off
/// shouldn't, is turned down.
nonisolated final class CodexConnection: @unchecked Sendable {
    private let process: AgentProcess
    private let lock = NSLock()
    private var nextID = 1
    /// The requests waiting for their results, which come as JSON.
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var listener: (@Sendable (AgentProcess.Event) -> Void)?
    private var starting: Task<Void, Error>?

    init(process: AgentProcess) {
        self.process = process
    }

    /// Starts the server and shakes hands, once; later calls wait for the first.
    func start() async throws {
        let task = lock.withLock {
            if let starting { return starting }
            let task = Task { [self] in
                process.listen { [weak self] in self?.handle($0) }
                try process.start()
                Log.commandLine.info("Running \(process.executable.path) app-server for Codex, kept for follow-ups")
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                _ = try await request("initialize", ["clientInfo": ["name": "meraline", "title": "Meraline", "version": version], "capabilities": NSNull()])
                try send(["method": "initialized"])
            }
            starting = task
            return task
        }
        try await task.value
    }

    /// Hands the server's notifications, and its end, to `listener`; nil stops.
    func listen(_ listener: (@Sendable (AgentProcess.Event) -> Void)?) {
        lock.withLock { self.listener = listener }
    }

    /// Sends a request and waits for its result.
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = lock.withLock {
            defer { nextID += 1 }
            return nextID
        }
        let message = try Self.line(["id": id, "method": method, "params": params])
        let result: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let ended = lock.withLock {
                    if process.hasEnded || Task.isCancelled { return true }
                    pending[id] = continuation
                    return false
                }
                if ended {
                    continuation.resume(throwing: Task.isCancelled ? CancellationError() : LLMError.provider(Self.endMessage(process.diagnostics)))
                    return
                }
                do {
                    try process.send(message)
                } catch {
                    if let waiting = lock.withLock({ pending.removeValue(forKey: id) }) { waiting.resume(throwing: error) }
                }
            }
        } onCancel: {
            if let waiting = lock.withLock({ pending.removeValue(forKey: id) }) { waiting.resume(throwing: CancellationError()) }
        }
        return (try? JSONSerialization.jsonObject(with: result)) as? [String: Any] ?? [:]
    }

    private func send(_ object: [String: Any]) throws {
        try process.send(try Self.line(object))
    }

    private static func line(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: .withoutEscapingSlashes)
        data.append(0x0A)
        return data
    }

    private static func endMessage(_ diagnostics: String) -> String {
        diagnostics.isEmpty ? "Codex stopped unexpectedly." : diagnostics
    }

    private func handle(_ event: AgentProcess.Event) {
        switch event {
        case .line(let line):
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
            let id = (object["id"] as? NSNumber)?.intValue
            let method = object["method"] as? String
            if let id, method == nil {
                guard let waiting = lock.withLock({ pending.removeValue(forKey: id) }) else { return }
                if let error = object["error"] as? [String: Any] {
                    waiting.resume(throwing: LLMError.provider(error["message"] as? String ?? "Codex turned the request down."))
                } else {
                    let result = (try? JSONSerialization.data(withJSONObject: object["result"] ?? [:], options: .fragmentsAllowed)) ?? Data()
                    waiting.resume(returning: result)
                }
            } else if let method, object["id"] != nil {
                Log.commandLine.info("Codex asked for \(method), which Meraline turns down")
                try? send(["id": object["id"] ?? NSNull(), "error": ["code": -32601, "message": "Meraline doesn’t answer \(method)."]])
            } else if method != nil {
                let listener = lock.withLock { self.listener }
                listener?(event)
            }
        case .ended(_, let diagnostics):
            let (waiting, listener) = lock.withLock {
                defer { pending = [:] }
                return (Array(pending.values), self.listener)
            }
            for continuation in waiting { continuation.resume(throwing: LLMError.provider(Self.endMessage(diagnostics))) }
            listener?(event)
        }
    }

    /// The models Codex offers, asked of an app server started for the purpose, for Settings.
    static func models(command: String) async throws -> [String] {
        guard let executable = CommandLineClient.resolve(command) else {
            throw LLMError.commandNotFound(.codex, command.trimmed)
        }
        let process = AgentProcess(
            executable: executable,
            arguments: ["app-server"],
            environment: CommandLineClient.environment(for: executable),
            directory: FileManager.default.temporaryDirectory
        )
        let connection = CodexConnection(process: process)
        defer { process.terminate() }
        return try await withThrowingTaskGroup(of: [String].self) { group in
            group.addTask {
                try await connection.start()
                let result = try await connection.request("model/list", ["includeHidden": false])
                let models = result["data"] as? [[String: Any]] ?? []
                return models.compactMap { $0["model"] as? String ?? $0["id"] as? String }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw LLMError.provider("Codex took too long to list its models.")
            }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }
}
