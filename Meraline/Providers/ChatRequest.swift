import Foundation

nonisolated struct ChatMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let role: Role
    let text: String
    var images: [ImageAttachment] = []
}

nonisolated struct ChatRequest: Sendable {
    let provider: Provider
    let settings: ProviderSettings
    let systemPrompt: String
    let messages: [ChatMessage]

    static let maximumOutputTokens = 16_000

    func urlRequest() throws -> URLRequest {
        let key = settings.apiKey.trimmed
        if provider.keyPolicy == .required && key.isEmpty {
            throw LLMError.missingKey(provider)
        }

        var headers = ["Content-Type": "application/json"]
        let path: String
        var query: [URLQueryItem] = []
        let body: [String: Any]

        switch provider {
        case .anthropic:
            path = "messages"
            headers["x-api-key"] = key
            headers["anthropic-version"] = "2023-06-01"
            body = anthropicBody
        case .openAI:
            path = "responses"
            headers["Authorization"] = "Bearer \(key)"
            body = openAIResponsesBody
        case .gemini:
            path = "models/\(settings.model.trimmed):streamGenerateContent"
            query = [URLQueryItem(name: "alt", value: "sse")]
            headers["x-goog-api-key"] = key
            body = geminiBody
        case .openRouter, .custom:
            path = "chat/completions"
            if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
            if provider == .openRouter { headers["X-Title"] = "Meraline" }
            body = chatCompletionsBody
        case .ollama:
            path = "api/chat"
            body = ollamaBody
        }

        guard var components = URLComponents(string: settings.baseURL.trimmed),
              components.scheme == "https" || components.scheme == "http",
              components.host?.isEmpty == false else {
            throw LLMError.invalidBaseURL(settings.baseURL)
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = "\(basePath)/\(path)"
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw LLMError.invalidBaseURL(settings.baseURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private var model: String { settings.model.trimmed }

    var anthropicBody: [String: Any] {
        [
            "model": model,
            "max_tokens": Self.maximumOutputTokens,
            "stream": true,
            "system": systemPrompt,
            "messages": messages.map { message in
                var content: [[String: Any]] = message.images.map { image in
                    ["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.base64]]
                }
                if !message.text.isEmpty { content.append(["type": "text", "text": message.text]) }
                return ["role": message.role.rawValue, "content": content]
            }
        ]
    }

    var openAIResponsesBody: [String: Any] {
        [
            "model": model,
            "instructions": systemPrompt,
            "stream": true,
            "store": false,
            "max_output_tokens": Self.maximumOutputTokens,
            "input": messages.map { message in
                let textType = message.role == .assistant ? "output_text" : "input_text"
                var content: [[String: Any]] = []
                if !message.text.isEmpty { content.append(["type": textType, "text": message.text]) }
                content += message.images.map { ["type": "input_image", "image_url": $0.dataURL] }
                return ["role": message.role.rawValue, "content": content]
            }
        ]
    }

    var geminiBody: [String: Any] {
        [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": messages.map { message in
                var parts: [[String: Any]] = message.images.map {
                    ["inline_data": ["mime_type": $0.mediaType, "data": $0.base64]]
                }
                if !message.text.isEmpty { parts.append(["text": message.text]) }
                return ["role": message.role == .assistant ? "model" : "user", "parts": parts]
            }
        ]
    }

    var chatCompletionsBody: [String: Any] {
        [
            "model": model,
            "stream": true,
            "messages": [["role": "system", "content": systemPrompt]] + messages.map { message -> [String: Any] in
                guard !message.images.isEmpty else {
                    return ["role": message.role.rawValue, "content": message.text]
                }
                var content: [[String: Any]] = []
                if !message.text.isEmpty { content.append(["type": "text", "text": message.text]) }
                content += message.images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
                return ["role": message.role.rawValue, "content": content]
            }
        ]
    }

    var ollamaBody: [String: Any] {
        [
            "model": model,
            "stream": true,
            "messages": [["role": "system", "content": systemPrompt]] + messages.map { message -> [String: Any] in
                var payload: [String: Any] = ["role": message.role.rawValue, "content": message.text]
                if !message.images.isEmpty { payload["images"] = message.images.map(\.base64) }
                return payload
            }
        ]
    }
}

nonisolated enum LLMError: LocalizedError, Equatable {
    case missingKey(Provider)
    case invalidBaseURL(String)
    case http(Int, String)
    case provider(String)
    case refused
    case truncated
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "Add your \(provider.name) API key in Settings."
        case .invalidBaseURL(let url): "“\(url)” isn’t a valid server address."
        case .http(let status, let message): "\(HTTPURLResponse.localizedString(forStatusCode: status).capitalized) (\(status)): \(message)"
        case .provider(let message): message
        case .refused: "The model declined to answer this request."
        case .truncated: "The answer was cut off because it reached the length limit."
        case .emptyResponse: "The model returned an empty answer."
        }
    }
}
