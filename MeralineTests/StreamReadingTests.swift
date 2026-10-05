import Foundation
import Testing
@testable import Meraline

/// Whether an HTTP provider's stream brought a whole answer. Until 2026-10-06 a connection that closed partway
/// ended the data just as a finished answer does, and the cut-off text was shown as the answer.
struct StreamReadingTests {
    /// The text of `payloads` read in order, as `LLMClient` reads a stream, and whether the data running out
    /// after them leaves a whole answer.
    private func read(_ payloads: [String], from provider: Provider) throws -> String {
        var reading = StreamReading(provider: provider)
        var text = ""
        for payload in payloads {
            let chunk = try reading.read(payload)
            if case .text(let piece) = chunk { text += piece }
            if chunk == .finished { break }
        }
        try reading.end()
        return text
    }

    private static let anthropic = [
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}"#,
        #"{"type":"message_stop"}"#,
    ]
    private static let openAI = [
        #"{"type":"response.output_text.delta","delta":"Hel"}"#,
        #"{"type":"response.output_text.delta","delta":"lo"}"#,
        #"{"type":"response.completed","response":{}}"#,
    ]
    private static let chatCompletions = [
        #"{"id":"1","choices":[{"index":0,"delta":{"content":"Hel"},"finish_reason":null}]}"#,
        #"{"id":"1","choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":null}]}"#,
        #"{"id":"1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
        #"{"id":"1","choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}"#,
        "[DONE]",
    ]
    private static let gemini = [
        #"{"candidates":[{"content":{"parts":[{"text":"Hel"}]}}]}"#,
        #"{"candidates":[{"content":{"parts":[{"text":"lo"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":2}}"#,
    ]
    private static let ollama = [
        #"{"model":"llama3.2","message":{"role":"assistant","content":"Hel"},"done":false}"#,
        #"{"model":"llama3.2","message":{"role":"assistant","content":"lo"},"done":false}"#,
        #"{"model":"llama3.2","message":{"role":"assistant","content":""},"done":true,"eval_count":2}"#,
    ]
    /// Every HTTP provider's whole answer, and how many of its last payloads say it is whole.
    private static let streams: [(provider: Provider, payloads: [String], closing: Int)] = [
        (.anthropic, anthropic, 1), (.openAI, openAI, 1), (.openRouter, chatCompletions, 3), (.custom, chatCompletions, 3),
        (.gemini, gemini, 1), (.ollama, ollama, 1),
    ]

    @Test func aWholeAnswerEndsWell() throws {
        for stream in Self.streams {
            #expect(try read(stream.payloads, from: stream.provider) == "Hello", "\(stream.provider)")
        }
    }

    @Test func dataThatRunsOutBeforeTheProvidersClosingWordIsAnInterruptedAnswer() {
        for stream in Self.streams {
            let cut = Array(stream.payloads.dropLast(stream.closing))
            #expect(throws: LLMError.interrupted, "\(stream.provider)") { try read(cut, from: stream.provider) }
            // Cut after its first words, too.
            #expect(throws: LLMError.interrupted, "\(stream.provider)") { try read([stream.payloads[0]], from: stream.provider) }
        }
    }

    @Test func aServerThatNeverSendsDoneStillEndsWithItsFinishReason() throws {
        // Some local servers close the stream after the chunk that says why the answer finished.
        let withoutDone = Array(Self.chatCompletions.dropLast(2))
        #expect(try read(withoutDone, from: .custom) == "Hello")
        #expect(try read(withoutDone, from: .openRouter) == "Hello")
        // And one that sends [DONE] without ever naming a reason.
        let onlyDone = Array(Self.chatCompletions.prefix(2)) + ["[DONE]"]
        #expect(try read(onlyDone, from: .custom) == "Hello")
    }

    @Test func theLastChunkMayCarryTextAndTheClosingWordTogether() throws {
        let ollama = [
            #"{"message":{"role":"assistant","content":"Hel"},"done":false}"#,
            #"{"message":{"role":"assistant","content":"lo"},"done":true}"#,
        ]
        #expect(try read(ollama, from: .ollama) == "Hello")
        let chat = [#"{"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":"stop"}]}"#]
        #expect(try read(chat, from: .custom) == "Hello")
    }

    @Test func noTextAtAllIsStillAnEmptyAnswer() {
        #expect(throws: LLMError.emptyResponse) { try read([], from: .anthropic) }
        #expect(throws: LLMError.emptyResponse) { try read(["[DONE]"], from: .custom) }
        #expect(throws: LLMError.emptyResponse) { try read([#"{"type":"message_stop"}"#], from: .anthropic) }
    }

    @Test func anInterruptedAnswerSaysSo() {
        #expect(LLMError.interrupted.localizedDescription == "The connection closed before the answer finished.")
    }

    @Test func onlyTheClosingPayloadsEndAnAnswer() {
        #expect(!StreamDecoder.endsAnswer(Self.chatCompletions[0], from: .custom), "finish_reason: null is no reason")
        #expect(StreamDecoder.endsAnswer(Self.chatCompletions[2], from: .custom))
        #expect(StreamDecoder.endsAnswer("[DONE]", from: .openRouter))
        #expect(!StreamDecoder.endsAnswer(Self.gemini[0], from: .gemini))
        #expect(StreamDecoder.endsAnswer(Self.gemini[1], from: .gemini))
        #expect(!StreamDecoder.endsAnswer(Self.ollama[0], from: .ollama), "done: false")
        #expect(StreamDecoder.endsAnswer(Self.ollama[2], from: .ollama))
        #expect(!StreamDecoder.endsAnswer("not json", from: .gemini))
    }
}
