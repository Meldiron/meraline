import EventSource
import Foundation

nonisolated enum LLMClient {
    private static let session = URLSession(configuration: .ephemeral)

    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        if request.provider.isCommandLine { return CommandLineClient.stream(request) }
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
                        throw LLMError.http(http.statusCode, StreamDecoder.errorMessage(from: body))
                    }

                    var receivedText = false
                    func handle(_ payload: String) throws -> Bool {
                        switch try StreamDecoder.decode(payload, from: request.provider) {
                        case .text(let text):
                            receivedText = true
                            continuation.yield(text)
                        case .finished:
                            return true
                        case .ignored:
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
                    if !receivedText { throw LLMError.emptyResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
