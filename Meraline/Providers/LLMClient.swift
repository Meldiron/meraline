import EventSource
import Foundation

nonisolated enum LLMClient {
    private static let session = URLSession(configuration: .ephemeral)

    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        if request.provider.isCommandLine { return CommandLineClient.stream(request) }
        if request.provider.isOnDevice { return AppleIntelligenceClient.stream(request) }
        if request.provider.isDecisionModel { return DecisionClient.stream(request) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request.urlRequest())
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.provider("The server sent a response Meraline doesn’t understand.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes where body.count < 64_000 { body.append(byte) }
                        Log.providers.error("\(request.provider.name) answered HTTP \(http.statusCode)")
                        throw LLMError.http(http.statusCode, StreamDecoder.errorMessage(from: body))
                    }

                    var reading = StreamReading(provider: request.provider)
                    func handle(_ payload: String) throws -> Bool {
                        if let report = StreamDecoder.usage(in: payload, from: request.provider) {
                            continuation.yield(.usage(report.tokens, adds: report.adds))
                        }
                        switch try reading.read(payload) {
                        case .text(let text):
                            continuation.yield(.text(text))
                        case .activity(let activity):
                            continuation.yield(.activity(activity))
                        case .finished:
                            return true
                        case .ignored, .prompt, .presented:
                            break
                        }
                        return false
                    }

                    if request.provider == .ollama {
                        for try await line in bytes.lines {
                            if try handle(line) { break }
                        }
                    } else {
                        for try await event in bytes.events {
                            if try handle(event.data) { break }
                        }
                    }
                    try reading.end()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// What an HTTP provider's stream has brought so far, payload by payload, so that when the data runs out it can
/// be told whether the answer is whole. A connection that closes partway ends the data just as a finished answer
/// does, and its cut-off text used to pass for the whole answer.
nonisolated struct StreamReading {
    let provider: Provider
    private(set) var receivedText = false
    /// The provider said the answer was whole: its closing event came, or a chunk said why it finished
    /// (`StreamDecoder.endsAnswer`).
    private(set) var ended = false

    init(provider: Provider) {
        self.provider = provider
    }

    /// What `payload` holds, noted for `end()`.
    mutating func read(_ payload: String) throws -> StreamChunk {
        if StreamDecoder.endsAnswer(payload, from: provider) { ended = true }
        let chunk = try StreamDecoder.decode(payload, from: provider)
        switch chunk {
        case .text: receivedText = true
        case .finished: ended = true
        default: break
        }
        return chunk
    }

    /// The data ran out. Throws when no answer came, or when it stopped short of the provider's word that it was
    /// whole.
    func end() throws {
        if !receivedText { throw LLMError.emptyResponse }
        if !ended { throw LLMError.interrupted }
    }
}
