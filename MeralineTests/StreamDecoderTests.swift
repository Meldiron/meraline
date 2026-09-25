import Foundation
import Testing
@testable import Meraline

struct StreamDecoderTests {
    @Test func anthropicTextDelta() throws {
        let payload = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        #expect(try StreamDecoder.decode(payload, from: .anthropic) == .text("Hello"))
    }

    @Test func anthropicThinkingDeltaIsIgnored() throws {
        let payload = #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}"#
        #expect(try StreamDecoder.decode(payload, from: .anthropic) == .ignored)
    }

    @Test func anthropicRefusalThrows() {
        let payload = #"{"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":1}}"#
        #expect(throws: LLMError.refused) { try StreamDecoder.decode(payload, from: .anthropic) }
    }

    @Test func anthropicErrorEventThrows() {
        let payload = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(throws: LLMError.provider("Overloaded")) { try StreamDecoder.decode(payload, from: .anthropic) }
    }

    @Test func openAIResponsesDelta() throws {
        let payload = #"{"type":"response.output_text.delta","item_id":"x","output_index":0,"content_index":0,"delta":"Hi"}"#
        #expect(try StreamDecoder.decode(payload, from: .openAI) == .text("Hi"))
        #expect(try StreamDecoder.decode(#"{"type":"response.completed","response":{}}"#, from: .openAI) == .finished)
    }

    @Test func openAIResponsesFailureThrows() {
        let payload = #"{"type":"response.failed","response":{"error":{"code":"server_error","message":"Boom"}}}"#
        #expect(throws: LLMError.provider("Boom")) { try StreamDecoder.decode(payload, from: .openAI) }
    }

    @Test func chatCompletionsDeltaAndDone() throws {
        let payload = #"{"id":"1","choices":[{"index":0,"delta":{"content":"Yo"},"finish_reason":null}]}"#
        #expect(try StreamDecoder.decode(payload, from: .openRouter) == .text("Yo"))
        #expect(try StreamDecoder.decode("[DONE]", from: .custom) == .finished)
    }

    @Test func geminiSkipsThoughtParts() throws {
        let payload = #"{"candidates":[{"content":{"parts":[{"text":"plan","thought":true},{"text":"Answer"}],"role":"model"}}]}"#
        #expect(try StreamDecoder.decode(payload, from: .gemini) == .text("Answer"))
    }

    @Test func geminiLengthLimitThrows() {
        let payload = #"{"candidates":[{"content":{"parts":[]},"finishReason":"MAX_TOKENS"}]}"#
        #expect(throws: LLMError.truncated) { try StreamDecoder.decode(payload, from: .gemini) }
    }

    @Test func ollamaLines() throws {
        #expect(try StreamDecoder.decode(#"{"message":{"role":"assistant","content":"Hey"},"done":false}"#, from: .ollama) == .text("Hey"))
        #expect(try StreamDecoder.decode(#"{"message":{"role":"assistant","content":""},"done":true}"#, from: .ollama) == .finished)
        #expect(throws: LLMError.provider("model not found")) {
            try StreamDecoder.decode(#"{"error":"model not found"}"#, from: .ollama)
        }
    }

    @Test func errorMessagesFromEveryShape() {
        #expect(StreamDecoder.errorMessage(from: Data(#"{"error":{"message":"Bad key"}}"#.utf8)) == "Bad key")
        #expect(StreamDecoder.errorMessage(from: Data(#"{"error":"Not found"}"#.utf8)) == "Not found")
        #expect(StreamDecoder.errorMessage(from: Data(#"{"message":"Nope"}"#.utf8)) == "Nope")
        #expect(StreamDecoder.errorMessage(from: Data("Gateway timeout".utf8)) == "Gateway timeout")
    }
}
