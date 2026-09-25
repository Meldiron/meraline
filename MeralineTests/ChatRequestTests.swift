import Foundation
import Testing
@testable import Meraline

struct ChatRequestTests {
    private func request(
        _ provider: Provider,
        key: String = "secret",
        baseURL: String? = nil,
        messages: [ChatMessage] = [ChatMessage(role: .user, text: "Hi")]
    ) -> ChatRequest {
        ChatRequest(
            provider: provider,
            settings: ProviderSettings(
                model: "test-model",
                baseURL: baseURL ?? provider.defaultBaseURL,
                apiKey: key,
                isEnabled: true
            ),
            systemPrompt: "Be brief.",
            messages: messages
        )
    }

    private func body(_ urlRequest: URLRequest) throws -> [String: Any] {
        let data = try #require(urlRequest.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func anthropicRequestUsesMessagesStreaming() throws {
        let urlRequest = try request(.anthropic).urlRequest()
        #expect(urlRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let json = try body(urlRequest)
        #expect(json["stream"] as? Bool == true)
        #expect(json["system"] as? String == "Be brief.")
        #expect(json["max_tokens"] as? Int == ChatRequest.maximumOutputTokens)
    }

    @Test func openAIRequestDoesNotStoreConversations() throws {
        let urlRequest = try request(.openAI).urlRequest()
        #expect(urlRequest.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let json = try body(urlRequest)
        #expect(json["store"] as? Bool == false)
        #expect(json["instructions"] as? String == "Be brief.")
    }

    @Test func openAIAssistantHistoryUsesOutputText() throws {
        let messages = [
            ChatMessage(role: .user, text: "Hi"),
            ChatMessage(role: .assistant, text: "Hello"),
            ChatMessage(role: .user, text: "More")
        ]
        let input = try #require(request(.openAI, messages: messages).openAIResponsesBody["input"] as? [[String: Any]])
        let assistant = try #require(input[1]["content"] as? [[String: Any]])
        #expect(assistant.first?["type"] as? String == "output_text")
    }

    @Test func geminiRequestStreamsServerSentEvents() throws {
        let urlRequest = try request(.gemini).urlRequest()
        #expect(urlRequest.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/test-model:streamGenerateContent?alt=sse")
        #expect(urlRequest.value(forHTTPHeaderField: "x-goog-api-key") == "secret")
    }

    @Test func customProviderOmitsAuthorizationWithoutKey() throws {
        let urlRequest = try request(.custom, key: "", baseURL: "http://localhost:1234/v1/").urlRequest()
        #expect(urlRequest.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil)
        let messages = try #require(body(urlRequest)["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "system")
    }

    @Test func ollamaRequestUsesChatEndpoint() throws {
        let urlRequest = try request(.ollama, key: "").urlRequest()
        #expect(urlRequest.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
    }

    @Test func missingKeyIsReported() {
        #expect(throws: LLMError.missingKey(.anthropic)) {
            try request(.anthropic, key: " ").urlRequest()
        }
    }

    @Test func invalidBaseURLIsReported() {
        #expect(throws: LLMError.invalidBaseURL("localhost")) {
            try request(.custom, baseURL: "localhost").urlRequest()
        }
    }

    @Test func imagesAreEncodedForEveryProvider() throws {
        let image = ImageAttachment(mediaType: "image/png", data: Data([1, 2, 3]))
        let message = ChatMessage(role: .user, text: "What is this?", images: [image])
        let messages = [message]

        let anthropic = try #require(request(.anthropic, messages: messages).anthropicBody["messages"] as? [[String: Any]])
        let anthropicContent = try #require(anthropic.first?["content"] as? [[String: Any]])
        #expect(anthropicContent.first?["type"] as? String == "image")

        let openAI = try #require(request(.openAI, messages: messages).openAIResponsesBody["input"] as? [[String: Any]])
        let openAIContent = try #require(openAI.first?["content"] as? [[String: Any]])
        #expect(openAIContent.last?["image_url"] as? String == image.dataURL)

        let gemini = try #require(request(.gemini, messages: messages).geminiBody["contents"] as? [[String: Any]])
        let geminiParts = try #require(gemini.first?["parts"] as? [[String: Any]])
        #expect(geminiParts.first?["inline_data"] != nil)

        let chat = try #require(request(.openRouter, messages: messages).chatCompletionsBody["messages"] as? [[String: Any]])
        let chatContent = try #require(chat.last?["content"] as? [[String: Any]])
        #expect(chatContent.last?["type"] as? String == "image_url")

        let ollama = try #require(request(.ollama, messages: messages).ollamaBody["messages"] as? [[String: Any]])
        #expect(ollama.last?["images"] as? [String] == [image.base64])
    }
}
