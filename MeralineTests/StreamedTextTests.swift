import Foundation
import Testing
@testable import Meraline

/// Streamed text joins its answer in batches (`ChatSession.textInterval`), in order with whatever else the
/// answer brings, and none of it is lost when the answer ends, fails, or is stopped. The tests set an interval
/// that never runs out, so only what the session does by itself adds the text, or a short one for the timer.
@MainActor
struct StreamedTextTests {
    private typealias Support = GameTestSupport
    private typealias Feed = AsyncThrowingStream<StreamOutput, Error>.Continuation

    private static let never: Duration = .seconds(3_600)

    /// A session asked one question, whose answer the test streams through the feed.
    private func asked(holdingTextFor interval: Duration) -> (session: ChatSession, feed: Feed) {
        let (stream, feed) = AsyncThrowingStream<StreamOutput, Error>.makeStream()
        let session = ChatSession(preferences: Support.preferences(), usage: UsageLedger(file: nil)) { _ in stream }
        session.textInterval = interval
        session.draft = "Tell me everything"
        session.send()
        return (session, feed)
    }

    /// Lets the session read its stream until `condition` holds. The stream is read a chunk at a time between the
    /// main actor and the threads behind it, so this waits by the clock, not by a count of turns.
    private func wait(for condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
    }

    private func answer(_ session: ChatSession) -> String {
        session.turns.last?.answer ?? ""
    }

    @Test func aFinishedAnswerHoldsEverythingThatStreamed() async {
        let chunks = (0..<675).map { "word\($0) " }
        for interval in [Self.never, .milliseconds(1), .zero] {
            let (session, feed) = asked(holdingTextFor: interval)
            for chunk in chunks { feed.yield(.text(chunk)) }
            feed.finish()
            await wait { !session.isStreaming }
            #expect(answer(session) == chunks.joined())
            #expect(session.turns.last?.isComplete == true)
            #expect(session.failure == nil)
        }
    }

    @Test func manyChunksChangeTheAnswerOnlyAFewTimes() async {
        let chunks = (0..<500).map { "word\($0) " }
        let (session, feed) = asked(holdingTextFor: Self.never)
        var seen: [String] = []
        func look() {
            let now = answer(session)
            if now != seen.last { seen.append(now) }
        }
        look()
        for chunk in chunks { feed.yield(.text(chunk)) }
        // What the answer took comes after the last chunk and leaves the text waiting, so once it is in, every
        // chunk has been read.
        feed.yield(.usage(TokenUsage(output: 500), adds: false))
        await wait {
            look()
            return session.turns.last?.usage != nil
        }
        #expect(session.turns.last?.usage?.output == 500)
        #expect(answer(session) == chunks[0], "the first words show at once, the rest wait")
        feed.finish()
        await wait {
            look()
            return !session.isStreaming
        }
        #expect(seen == ["", chunks[0], chunks.joined()], "500 chunks changed the answer twice")
    }

    @Test func heldTextGoesInWhenItsTimeIsUp() async {
        let (session, feed) = asked(holdingTextFor: .milliseconds(5))
        feed.yield(.text("First"))
        feed.yield(.text(" second"))
        feed.yield(.text(" third"))
        let deadline = Date.now.addingTimeInterval(10)
        while answer(session) != "First second third", Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(answer(session) == "First second third")
        #expect(session.isStreaming, "with the stream still open")
        feed.yield(.text(" fourth"))
        feed.finish()
        await wait { !session.isStreaming }
        #expect(answer(session) == "First second third fourth")
    }

    @Test func textGoesInBeforeWhatFollowsIt() async {
        let (session, feed) = asked(holdingTextFor: Self.never)
        feed.yield(.text("Let me"))
        feed.yield(.text(" look"))
        feed.yield(.text(" that up."))
        feed.yield(.activity(.searching("swift")))
        await wait { session.turns.last?.activity != nil }
        #expect(answer(session) == "Let me look that up.", "the words before the search are in when it shows")
        #expect(session.turns.last?.tools == [.searching("swift")])

        // After a tool the answer starts over, with its first words at once.
        feed.yield(.text("Swift"))
        feed.yield(.text(" is"))
        feed.yield(.text(" a language."))
        let prompt = AgentPrompt(id: "req-1", kind: .permission(.tool("Write"), detail: "note.md"))
        feed.yield(.prompt(prompt, nil))
        await wait { session.turns.last?.prompts.isEmpty == false }
        #expect(answer(session) == "Swift is a language.", "and the words before an ask are in when it shows")
        #expect(session.turns.last?.activity == nil)

        // What the answer took is no part of what shows, so the text keeps waiting.
        feed.yield(.text(" Anything"))
        feed.yield(.text(" else?"))
        feed.yield(.usage(TokenUsage(output: 9), adds: false))
        await wait { session.turns.last?.usage != nil }
        #expect(answer(session) == "Swift is a language.")
        feed.finish()
        await wait { !session.isStreaming }
        #expect(answer(session) == "Swift is a language. Anything else?")
    }

    @Test func aStoppedAnswerKeepsWhatArrived() async {
        let (session, feed) = asked(holdingTextFor: Self.never)
        feed.yield(.text("Once"))
        feed.yield(.text(" upon"))
        feed.yield(.text(" a time"))
        feed.yield(.usage(TokenUsage(output: 3), adds: false))
        await wait { session.turns.last?.usage != nil }
        #expect(answer(session) == "Once")
        session.stop()
        await wait { !session.isStreaming }
        #expect(!session.isStreaming)
        #expect(answer(session) == "Once upon a time")
        #expect(session.turns.last?.isComplete == true)
        #expect(session.failure == nil)
    }

    @Test func aFailedAnswerKeepsWhatArrived() async {
        let (session, feed) = asked(holdingTextFor: Self.never)
        feed.yield(.text("Once"))
        feed.yield(.text(" upon"))
        feed.finish(throwing: LLMError.truncated)
        await wait { !session.isStreaming }
        #expect(answer(session) == "Once upon")
        #expect(session.failure == LLMError.truncated.localizedDescription)
    }

    @Test func aChatLeftMidAnswerKeepsWhatArrivedAndPassesNoneOn() async {
        let (session, feed) = asked(holdingTextFor: .milliseconds(5))
        feed.yield(.text("Old"))
        feed.yield(.text(" words"))
        feed.yield(.usage(TokenUsage(output: 2), adds: false))
        await wait { session.turns.last?.usage != nil }
        session.reset()
        #expect(session.history.first?.turns.map(\.answer) == ["Old words"], "the chat goes to Recent Chats whole")
        #expect(session.turns.isEmpty)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(session.turns.isEmpty, "and nothing of it comes after it")
        #expect(session.history.first?.turns.map(\.answer) == ["Old words"])
    }

    @Test func aGamesMoveIsJudgedWhole() async {
        let move = "A cat sat waiting by the door | floor, more, four"
        let whole = Support.session(ScriptedModel([move]))
        whole.dice = GameDice(seed: 2)
        whole.startGame(.rhymeDuel)
        whole.send()
        await wait { !whole.isStreaming }

        let pieces = ChatSession(preferences: Support.preferences(), usage: UsageLedger(file: nil)) { _ in
            AsyncThrowingStream { continuation in
                for (index, word) in move.components(separatedBy: " ").enumerated() {
                    continuation.yield(.text(index == 0 ? word : " \(word)"))
                }
                continuation.finish()
            }
        }
        pieces.textInterval = Self.never
        pieces.dice = GameDice(seed: 2)
        pieces.startGame(.rhymeDuel)
        pieces.send()
        await wait { !pieces.isStreaming }
        #expect(!whole.turns.isEmpty)
        #expect(pieces.turns.map(\.answer) == whole.turns.map(\.answer))
        #expect(pieces.turns.last?.isComplete == true)
        #expect(pieces.isYourMove == whole.isYourMove)
    }
}
