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

    @Test func usageIsReadFromEveryProvider() throws {
        let start = #"{"type":"message_start","message":{"id":"m","model":"claude-sonnet-5","usage":{"input_tokens":25,"cache_creation_input_tokens":3,"cache_read_input_tokens":7,"output_tokens":1}}}"#
        #expect(StreamDecoder.usage(in: start, from: .anthropic) == UsageReport(tokens: TokenUsage(input: 25, output: nil, cacheRead: 7, cacheWrite: 3, model: "claude-sonnet-5")))
        let delta = #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}"#
        #expect(StreamDecoder.usage(in: delta, from: .anthropic) == UsageReport(tokens: TokenUsage(output: 15)))
        #expect(StreamDecoder.usage(in: #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"usage"}}"#, from: .anthropic) == nil)

        let completed = #"{"type":"response.completed","response":{"model":"gpt-5-mini","usage":{"input_tokens":36,"input_tokens_details":{"cached_tokens":6},"output_tokens":87}}}"#
        #expect(StreamDecoder.usage(in: completed, from: .openAI) == UsageReport(tokens: TokenUsage(input: 30, output: 87, cacheRead: 6, model: "gpt-5-mini")), "cached tokens come out of the input")

        let last = #"{"id":"1","model":"anthropic/claude-sonnet-5","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":20,"prompt_tokens_details":{"cached_tokens":4},"cost":0.000123}}"#
        #expect(StreamDecoder.usage(in: last, from: .openRouter) == UsageReport(tokens: TokenUsage(input: 6, output: 20, cacheRead: 4, cost: 0.000123, model: "anthropic/claude-sonnet-5")))
        #expect(try StreamDecoder.decode(last, from: .openRouter) == .ignored, "no words in the last chunk")
        #expect(StreamDecoder.usage(in: #"{"id":"1","choices":[{"index":0,"delta":{"content":"Yo"}}]}"#, from: .custom) == nil)

        let gemini = #"{"candidates":[{"content":{"parts":[{"text":"Hi"}]}}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":5,"thoughtsTokenCount":3,"cachedContentTokenCount":2},"modelVersion":"gemini-3.6-flash"}"#
        #expect(StreamDecoder.usage(in: gemini, from: .gemini) == UsageReport(tokens: TokenUsage(input: 10, output: 8, cacheRead: 2, model: "gemini-3.6-flash")), "thoughts are output")
        #expect(try StreamDecoder.decode(gemini, from: .gemini) == .text("Hi"), "and the words still read")

        let ollama = #"{"model":"llama3.2","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":26,"eval_count":298}"#
        #expect(StreamDecoder.usage(in: ollama, from: .ollama) == UsageReport(tokens: TokenUsage(input: 26, output: 298, model: "llama3.2")))

        let result = #"{"type":"result","total_cost_usd":0.019586,"usage":{"input_tokens":10,"cache_creation_input_tokens":9232,"cache_read_input_tokens":0,"output_tokens":32},"modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":907,"outputTokens":43,"cacheReadInputTokens":0,"cacheCreationInputTokens":9232,"costUSD":0.019586}}}"#
        #expect(StreamDecoder.usage(in: result, from: .claudeCode) == UsageReport(tokens: TokenUsage(input: 907, output: 43, cacheRead: 0, cacheWrite: 9232, cost: 0.019586, model: "claude-haiku-4-5-20251001")), "by model, which the cost follows")
        let bare = #"{"type":"result","total_cost_usd":0.01,"usage":{"input_tokens":10,"cache_creation_input_tokens":2,"cache_read_input_tokens":1,"output_tokens":32}}"#
        #expect(StreamDecoder.usage(in: bare, from: .claudeCode) == UsageReport(tokens: TokenUsage(input: 10, output: 32, cacheRead: 1, cacheWrite: 2, cost: 0.01)))
        let wrapped = #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}}"#
        #expect(StreamDecoder.usage(in: wrapped, from: .claudeCode) == UsageReport(tokens: TokenUsage(output: 9)))

        let codex = #"{"method":"thread/tokenUsage/updated","params":{"threadId":"t","turnId":"u","tokenUsage":{"last":{"inputTokens":50,"cachedInputTokens":10,"outputTokens":5,"reasoningOutputTokens":0,"totalTokens":55},"total":{"inputTokens":100,"cachedInputTokens":20,"outputTokens":30,"reasoningOutputTokens":5,"totalTokens":130,"cacheWriteInputTokens":0}}}}"#
        #expect(StreamDecoder.usage(in: codex, from: .codex) == UsageReport(tokens: TokenUsage(input: 80, output: 30, cacheRead: 20, cacheWrite: 0)), "the thread's total")
        #expect(StreamDecoder.usage(in: #"{"method":"item/completed","params":{"item":{"type":"agentMessage"}}}"#, from: .codex) == nil)

        let step = #"{"type":"step_finish","timestamp":1,"sessionID":"s","part":{"type":"step-finish","reason":"stop","cost":0.0012,"tokens":{"input":21772,"output":110,"reasoning":4,"cache":{"read":3,"write":0}}}}"#
        #expect(StreamDecoder.usage(in: step, from: .opencode) == UsageReport(tokens: TokenUsage(input: 21772, output: 114, cacheRead: 3, cacheWrite: 0, cost: 0.0012), adds: true), "steps add up")
        #expect(StreamDecoder.usage(in: "not json", from: .opencode) == nil)
        #expect(StreamDecoder.usage(in: "anything", from: .apple) == nil)
    }

    @Test func aRunningTotalGivesTheTurnsShare() {
        let total = TokenUsage(input: 100, output: 30, cacheRead: 20, cost: 0.5)
        #expect(total.subtracting(TokenUsage(input: 60, output: 10, cacheRead: 20, cost: 0.2)) == TokenUsage(input: 40, output: 20, cacheRead: 0, cost: 0.3))
        #expect(total.subtracting(.zero) == total)
        #expect(TokenUsage(input: 5).subtracting(TokenUsage(input: 9)) == TokenUsage(input: 0), "never below zero")
    }

    @Test func errorMessagesFromEveryShape() {
        #expect(StreamDecoder.errorMessage(from: Data(#"{"error":{"message":"Bad key"}}"#.utf8)) == "Bad key")
        #expect(StreamDecoder.errorMessage(from: Data(#"{"error":"Not found"}"#.utf8)) == "Not found")
        #expect(StreamDecoder.errorMessage(from: Data(#"{"message":"Nope"}"#.utf8)) == "Nope")
        #expect(StreamDecoder.errorMessage(from: Data("Gateway timeout".utf8)) == "Gateway timeout")
    }
}
