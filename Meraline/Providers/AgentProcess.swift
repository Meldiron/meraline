import Foundation

/// A command-line agent that keeps running between questions: its process with stdin open for what Meraline
/// sends, each line it prints handed to the listener of the moment, and the end of its stderr kept for when it
/// fails. Lines that come while nobody listens, between answers, are dropped.
nonisolated final class AgentProcess: @unchecked Sendable {
    enum Event: Sendable {
        case line(String)
        /// The process is gone, with how it exited and the end of what it said on stderr.
        case ended(status: Int32, diagnostics: String)
    }

    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let directory: URL

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let lock = NSLock()
    private var listener: (@Sendable (Event) -> Void)?
    private var errorTail = Data()
    private var endedEvent: Event?
    private static let errorLimit = 8_192

    init(executable: URL, arguments: [String], environment: [String: String], directory: URL) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.directory = directory
    }

    var isRunning: Bool { process.isRunning }

    /// Whether the process has ended.
    var hasEnded: Bool { lock.withLock { endedEvent != nil } }

    func start() throws {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let exit = AsyncStream<Int32> { stream in
            process.terminationHandler = { stream.yield($0.terminationStatus); stream.finish() }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.lock.withLock {
                self.errorTail.append(data)
                if self.errorTail.count > 2 * Self.errorLimit { self.errorTail.removeFirst(self.errorTail.count - Self.errorLimit) }
            }
        }
        try process.run()
        let lines = CommandLineClient.lines(of: output.fileHandleForReading)
        Task.detached { [weak self] in
            for await line in lines { self?.deliver(.line(line)) }
            var status: Int32 = 0
            for await code in exit { status = code }
            guard let self else { return }
            let event = Event.ended(status: status, diagnostics: self.diagnostics)
            self.lock.withLock { self.endedEvent = event }
            self.deliver(event)
        }
    }

    /// Hands every line from now on, and the end, to `listener`; nil stops listening. A listener that comes after
    /// the end hears of it at once.
    func listen(_ listener: (@Sendable (Event) -> Void)?) {
        let ended = lock.withLock {
            self.listener = listener
            return endedEvent
        }
        if let ended, let listener { listener(ended) }
    }

    func send(_ data: Data) throws {
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    /// The end of what the process said on stderr, for an error message.
    var diagnostics: String {
        let data = lock.withLock { errorTail.suffix(Self.errorLimit) }
        return String(decoding: data, as: UTF8.self).trimmed
    }

    private func deliver(_ event: Event) {
        let listener = lock.withLock { self.listener }
        listener?(event)
    }
}
