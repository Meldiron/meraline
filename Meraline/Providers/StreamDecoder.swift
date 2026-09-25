import Foundation

nonisolated enum StreamChunk: Equatable, Sendable {
    case text(String)
    case finished
    case ignored
}

nonisolated enum StreamDecoder {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func decode(_ payload: String, from provider: Provider) throws -> StreamChunk {
        switch provider {
        case .anthropic: try anthropic(payload)
        case .openAI: try openAIResponses(payload)
        case .gemini: try gemini(payload)
        case .openRouter, .custom: try chatCompletions(payload)
        case .ollama: try ollama(payload)
        }
    }

    static func errorMessage(from data: Data) -> String {
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message ?? envelope.message, !message.isEmpty {
            return message
        }
        let text = String(decoding: data.prefix(500), as: UTF8.self).trimmed
        return text.isEmpty ? "The request failed." : text
    }

    private static func anthropic(_ payload: String) throws -> StreamChunk {
        let event = try decoder.decode(AnthropicEvent.self, from: Data(payload.utf8))
        switch event.type {
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text { return .text(text) }
        case "message_delta":
            switch event.delta?.stopReason {
            case "refusal": throw LLMError.refused
            case "max_tokens": throw LLMError.truncated
            default: break
            }
        case "message_stop":
            return .finished
        case "error":
            throw LLMError.provider(event.error?.message ?? "Anthropic reported an error.")
        default:
            break
        }
        return .ignored
    }

    private static func openAIResponses(_ payload: String) throws -> StreamChunk {
        let data = Data(payload.utf8)
        let kind = try decoder.decode(EventKind.self, from: data).type
        switch kind {
        case "response.output_text.delta":
            return .text(try decoder.decode(ResponsesTextDelta.self, from: data).delta)
        case "response.completed":
            return .finished
        case "response.incomplete":
            throw LLMError.truncated
        case "response.failed":
            let failure = try decoder.decode(ResponsesFailure.self, from: data)
            throw LLMError.provider(failure.response.error?.message ?? "OpenAI couldn’t complete the response.")
        case "error":
            let error = try decoder.decode(ErrorDetail.self, from: data)
            throw LLMError.provider(error.message ?? "OpenAI reported an error.")
        default:
            return .ignored
        }
    }

    private static func chatCompletions(_ payload: String) throws -> StreamChunk {
        if payload == "[DONE]" { return .finished }
        let chunk = try decoder.decode(ChatCompletionChunk.self, from: Data(payload.utf8))
        if let message = chunk.error?.message { throw LLMError.provider(message) }
        guard let choice = chunk.choices?.first else { return .ignored }
        if choice.finishReason == "length" { throw LLMError.truncated }
        if let content = choice.delta?.content, !content.isEmpty { return .text(content) }
        return .ignored
    }

    private static func gemini(_ payload: String) throws -> StreamChunk {
        let chunk = try decoder.decode(GeminiChunk.self, from: Data(payload.utf8))
        if let message = chunk.error?.message { throw LLMError.provider(message) }
        if let reason = chunk.promptFeedback?.blockReason {
            throw LLMError.provider("Gemini blocked this request (\(reason)).")
        }
        guard let candidate = chunk.candidates?.first else { return .ignored }
        let text = candidate.content?.parts?.compactMap { $0.thought == true ? nil : $0.text }.joined() ?? ""
        if !text.isEmpty { return .text(text) }
        switch candidate.finishReason {
        case "MAX_TOKENS": throw LLMError.truncated
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII": throw LLMError.refused
        default: return .ignored
        }
    }

    private static func ollama(_ payload: String) throws -> StreamChunk {
        let chunk = try decoder.decode(OllamaChunk.self, from: Data(payload.utf8))
        if let error = chunk.error { throw LLMError.provider(error) }
        if let content = chunk.message?.content, !content.isEmpty { return .text(content) }
        return chunk.done == true ? .finished : .ignored
    }
}

private nonisolated struct EventKind: Decodable {
    let type: String
}

private nonisolated struct ErrorDetail: Decodable {
    let message: String?
}

private nonisolated struct ErrorEnvelope: Decodable {
    let error: ErrorValue?
    let message: String?

    enum ErrorValue: Decodable {
        case detail(ErrorDetail)
        case text(String)

        var message: String? {
            switch self {
            case .detail(let detail): detail.message
            case .text(let text): text
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .detail(try container.decode(ErrorDetail.self))
            }
        }
    }
}

private nonisolated struct AnthropicEvent: Decodable {
    let type: String
    let delta: Delta?
    let error: ErrorDetail?

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let stopReason: String?
    }
}

private nonisolated struct ResponsesTextDelta: Decodable {
    let delta: String
}

private nonisolated struct ResponsesFailure: Decodable {
    let response: Response

    struct Response: Decodable {
        let error: ErrorDetail?
    }
}

private nonisolated struct ChatCompletionChunk: Decodable {
    let choices: [Choice]?
    let error: ErrorDetail?

    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private nonisolated struct GeminiChunk: Decodable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let error: ErrorDetail?

    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
        let thought: Bool?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }
}

private nonisolated struct OllamaChunk: Decodable {
    let message: Message?
    let done: Bool?
    let error: String?

    struct Message: Decodable {
        let content: String?
    }
}
