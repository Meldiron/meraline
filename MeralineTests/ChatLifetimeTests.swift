import Foundation
import Testing
@testable import Meraline

/// How long a chat lasts, how much it and Recent Chats may hold, and what happens when macOS clears a
/// chat's workspace.
@MainActor
struct ChatLifetimeTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.lifetime.\(UUID().uuidString)")

    private func exists(_ url: URL?) -> Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// A session with a ready LLM and a ready agent, asking the agent, so every chat gets a workspace.
    private func agentSession(_ model: ScriptedModel, preferences: Preferences = GameTestSupport.preferences()) -> ChatSession {
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.mode = .agent
        return ChatSession(preferences: preferences, workspaceRoot: root) { model.stream($0) }
    }

    private func write(_ files: [String], in folder: URL) throws {
        for path in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
    }

    // MARK: The chat's time

    @Test func aMessageGivesTheChatThirtyMinutes() async throws {
        let session = GameTestSupport.session(ScriptedModel(["Hello"]))
        #expect(session.expiresAt == nil)
        await GameTestSupport.play("Hi", in: session)
        let expiresAt = try #require(session.expiresAt)
        #expect(abs(expiresAt.timeIntervalSinceNow - ChatSession.chatLifetime) < 5)
        session.reset()
        #expect(session.expiresAt == nil)
    }

    @Test func aGameStartsItsTimeWithItsFirstMove() async throws {
        let session = GameTestSupport.session(ScriptedModel(["OK: salmon"]))
        session.startGame(.wordFootball)
        #expect(session.expiresAt == nil, "nothing to lose before anyone moves")
        session.expireChats(now: .now.addingTimeInterval(ChatSession.chatLifetime * 2))
        #expect(session.game == .wordFootball, "a game nobody has moved in doesn't run out")
        await GameTestSupport.play("apple", in: session)
        let expiresAt = try #require(session.expiresAt)
        #expect(abs(expiresAt.timeIntervalSinceNow - ChatSession.chatLifetime) < 5)
    }

    @Test func theOpenChatGoesWithItsWorkspaceWhenItsTimeRunsOut() async throws {
        let session = agentSession(ScriptedModel(["Hello"]))
        await GameTestSupport.play("Hi", in: session)
        let workspace = try #require(session.workspace).url
        let expiresAt = try #require(session.expiresAt)
        session.draft = "Typed, not sent"

        session.expireChats(now: expiresAt.addingTimeInterval(-1))
        #expect(session.turns.count == 1)

        session.expireChats(now: expiresAt.addingTimeInterval(1))
        #expect(session.turns.isEmpty)
        #expect(session.expiresAt == nil)
        // Gone, not moved to Recent Chats.
        #expect(session.history.isEmpty)
        #expect(session.workspace == nil)
        #expect(!exists(workspace))
        #expect(session.draft == "Typed, not sent")
        ChatWorkspace.removeAll(in: root)
    }

    @Test func aChatKeepsItsTimeInRecentChats() async throws {
        let session = agentSession(ScriptedModel(["One", "Two"]))
        await GameTestSupport.play("First", in: session)
        let first = try #require(session.workspace).url
        let deadline = try #require(session.expiresAt)
        session.reset()
        #expect(session.history.first?.expiresAt == deadline)

        try await Task.sleep(for: .milliseconds(50))
        await GameTestSupport.play("Second", in: session)
        let second = try #require(session.workspace).url
        let secondDeadline = try #require(session.expiresAt)
        session.expireChats(now: deadline.addingTimeInterval(secondDeadline.timeIntervalSince(deadline) / 2))
        // The recent chat went; the open one had its time started over by its own message.
        #expect(session.history.isEmpty)
        #expect(!exists(first))
        #expect(session.turns.count == 1)
        #expect(exists(second))
        ChatWorkspace.removeAll(in: root)
    }

    @Test func theTimersButtonsAddTimeAndReopeningKeepsIt() async throws {
        let session = GameTestSupport.session(ScriptedModel(["Hello"]))
        session.addTime(minutes: 5)
        #expect(session.expiresAt == nil, "no chat, no time to add to")
        await GameTestSupport.play("Hi", in: session)
        let first = try #require(session.expiresAt)
        session.addTime(minutes: 5)
        #expect(session.expiresAt == first.addingTimeInterval(5 * 60))
        session.addTime(minutes: 30)
        let added = try #require(session.expiresAt)
        #expect(added == first.addingTimeInterval(35 * 60))

        // Recent Chats keeps the time added, and so does reopening.
        session.reset()
        #expect(session.history.first?.expiresAt == added)
        let id = try #require(session.history.first?.id)
        try await Task.sleep(for: .milliseconds(20))
        session.reopen(id)
        #expect(session.expiresAt == added)
    }

    @Test func aMessageNeverTakesAwayTimeAdded() async throws {
        let session = GameTestSupport.session(ScriptedModel(["One", "Two"]))
        await GameTestSupport.play("First", in: session)
        session.addTime(minutes: 30)
        let added = try #require(session.expiresAt)
        await GameTestSupport.play("Second", in: session)
        #expect(session.expiresAt == added, "an hour left beats a fresh 30 minutes")
    }

    @Test func anAnswerStillComingKeepsItsChat() async throws {
        let held = HeldStream()
        let session = ChatSession(preferences: GameTestSupport.preferences()) { held.stream($0) }
        session.draft = "A long one?"
        session.send()
        await Task.yield()
        #expect(session.isStreaming)

        session.expireChats(now: .now.addingTimeInterval(ChatSession.chatLifetime * 2))
        #expect(session.turns.count == 1)

        held.continuation?.finish()
        await GameTestSupport.settle(session)
        #expect(!session.isStreaming)
        // The end of the answer starts the time over.
        #expect(try #require(session.expiresAt).timeIntervalSinceNow > ChatSession.chatLifetime - 5)
    }

    @Test func theTimerSaysMinutesThenSeconds() {
        let now = Date.now
        #expect(ChatTimer.remaining(until: now.addingTimeInterval(30 * 60), now: now) == "30 min left")
        #expect(ChatTimer.remaining(until: now.addingTimeInterval(29 * 60 + 59), now: now) == "29 min left")
        #expect(ChatTimer.remaining(until: now.addingTimeInterval(60), now: now) == "1 min left")
        #expect(ChatTimer.remaining(until: now.addingTimeInterval(59), now: now) == "59 s left")
        #expect(ChatTimer.remaining(until: now.addingTimeInterval(0.2), now: now) == "1 s left")
        #expect(ChatTimer.remaining(until: now.addingTimeInterval(-5), now: now) == "1 s left")
    }

    @Test func theTimerTurnsPinkAsItReadsFiveMinutes() {
        let now = Date.now
        #expect(!ChatTimer.isRunningOut(until: now.addingTimeInterval(30 * 60), now: now))
        #expect(!ChatTimer.isRunningOut(until: now.addingTimeInterval(6 * 60), now: now))
        #expect(ChatTimer.remaining(until: now.addingTimeInterval(5 * 60 + 59), now: now) == "5 min left")
        #expect(ChatTimer.isRunningOut(until: now.addingTimeInterval(5 * 60 + 59), now: now))
        #expect(ChatTimer.isRunningOut(until: now.addingTimeInterval(59), now: now))
        #expect(ChatTimer.isRunningOut(until: now.addingTimeInterval(-5), now: now))
    }

    // MARK: Limits

    @Test func recentChatsLeaveRoomForTheOpenOneUnderTheLimit() {
        var history: [ChatSession.PastChat] = []
        for index in 1...(ChatSession.chatLimit + 5) {
            var turn = ChatSession.Turn(question: "Question \(index)", images: [])
            turn.answer = "Answer"
            history = ChatSession.archiving([turn], into: history)
        }
        #expect(history.count == ChatSession.chatLimit - 1)
        #expect(history.first?.title == "Question \(ChatSession.chatLimit + 5)")
    }

    @Test func aChatThatDropsOffTheEndTakesItsWorkspace() async throws {
        let model = ScriptedModel(Array(repeating: "Ok", count: ChatSession.chatLimit))
        let preferences = GameTestSupport.preferences()
        let session = agentSession(model, preferences: preferences)
        await GameTestSupport.play("With a workspace", in: session)
        let oldest = try #require(session.workspace).url
        session.reset()

        preferences.mode = .llm
        for index in 1..<ChatSession.chatLimit - 1 {
            await GameTestSupport.play("Question \(index)", in: session)
            session.reset()
        }
        #expect(session.history.count == ChatSession.chatLimit - 1)
        #expect(exists(oldest))

        await GameTestSupport.play("One more", in: session)
        session.reset()
        #expect(session.history.count == ChatSession.chatLimit - 1)
        #expect(!exists(oldest))
        ChatWorkspace.removeAll(in: root)
    }

    @Test func aQuestionPastTheChatsMemoryLimitStaysInTheInput() async {
        let session = GameTestSupport.session(ScriptedModel(["Hello"]))
        session.byteLimit = 40
        await GameTestSupport.play("Hi", in: session)
        #expect(session.turns.count == 1)

        session.draft = "A question too long for what is left of forty bytes"
        session.send()
        #expect(session.turns.count == 1)
        #expect(!session.isStreaming)
        #expect(session.failure?.hasPrefix("This chat is full") == true)
        #expect(session.draft == "A question too long for what is left of forty bytes")
    }

    @Test func aWorkspaceTakesInAtMostItsLimit() async throws {
        let workspace = root.appending(path: "Workspace")
        try write(["kept.txt", "made by the agent.txt"], in: workspace)
        try write(["notes/a.txt", "notes/b.txt", "big/1", "big/2", "big/3", "big/4", "c.txt", "d.txt"], in: root)

        // Two in the workspace already leave room for one more of three.
        let notes = try FileAttachment.make(from: root.appending(path: "notes"), avoiding: [])
        await #expect(throws: AttachmentError.workspaceFull("notes")) {
            try await FileAttachment.copy([notes], into: workspace, limit: 3)
        }
        let big = try FileAttachment.make(from: root.appending(path: "big"), avoiding: [])
        await #expect(throws: AttachmentError.tooManyFiles("big")) {
            try await FileAttachment.copy([big], into: workspace, limit: 3)
        }
        try await FileAttachment.copy([try FileAttachment.make(from: root.appending(path: "c.txt"), avoiding: [])], into: workspace, limit: 3)
        #expect(exists(workspace.appending(path: "c.txt")))
        await #expect(throws: AttachmentError.workspaceFull("d.txt")) {
            try await FileAttachment.copy([try FileAttachment.make(from: root.appending(path: "d.txt"), avoiding: [])], into: workspace, limit: 3)
        }
        // Sending the same file again replaces its copy rather than counting it twice.
        try await FileAttachment.copy([try FileAttachment.make(from: root.appending(path: "c.txt"), avoiding: [])], into: workspace, limit: 3)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: A workspace macOS cleared

    @Test func aWorkspaceThatWentMissingIsMadeAgainAndTheQuestionSaysSo() async throws {
        let session = agentSession(ScriptedModel(["One", "Two", "Three"]))
        await GameTestSupport.play("First", in: session)
        let workspace = try #require(session.workspace)
        try FileManager.default.removeItem(at: workspace.url)
        #expect(!workspace.exists)

        await GameTestSupport.play("Second", in: session)
        #expect(workspace.exists)
        #expect(session.workspace == workspace)
        #expect(session.turns.map(\.answer) == ["One", "Two"])
        #expect(session.turns.first?.notice == nil)
        #expect(session.turns.last?.notice == ChatSession.remadeWorkspaceNotice)

        await GameTestSupport.play("Third", in: session)
        #expect(session.turns.last?.notice == nil)
        ChatWorkspace.removeAll(in: root)
    }

    // MARK: Diagnostics

    @Test func workspaceUsageCountsWithoutNames() throws {
        let parent = root.appending(path: "parent")
        let mine = parent.appending(path: "123")
        try write(["A/one.txt", "A/sub/two.txt", "B/three.txt", ".removing-X/gone.txt"], in: mine)
        try FileManager.default.createDirectory(at: parent.appending(path: "456"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: parent.appending(path: "notes"), withIntermediateDirectories: true)

        let usage = ChatWorkspace.usage(in: mine, parent: parent)
        #expect(usage.folders == 2)
        #expect(usage.items == 4)
        #expect(usage.mostItems == 3)
        #expect(usage.bytes == Int64("A/one.txt".utf8.count + "A/sub/two.txt".utf8.count + "B/three.txt".utf8.count))
        #expect(usage.otherProcesses == 1)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func theReportSaysWhatTheChatsHold() async {
        let session = GameTestSupport.session(ScriptedModel(["Hello"]))
        await GameTestSupport.play("Hi", in: session)
        let storage = await Diagnostics.storage(of: session)
        #expect(storage.openTurns == 1)
        #expect(storage.recentChats == 0)
        #expect(storage.chatBytes == "Hi".utf8.count + "Hello".utf8.count)
        #expect((storage.nextExpiry ?? 0) > ChatSession.chatLifetime - 5)

        let updates = Diagnostics.UpdateStatus(isAvailable: false, channel: .stable, checksAutomatically: false, downloadsAutomatically: false, lastCheck: nil, state: "")
        let report = Diagnostics.report(preferences: GameTestSupport.preferences(), updates: updates, entries: [], storage: storage)
        #expect(report.contains("### Storage"))
        #expect(report.contains("- Chats in memory: an open chat of 1 turn(s) and 0 recent"))
        #expect(report.contains("- Chat lifetime: at least 30 minutes after the last message, the next goes in 30 min"))
        #expect(!report.contains("Hello"))
        #expect(!Diagnostics.report(preferences: GameTestSupport.preferences(), updates: updates, entries: []).contains("### Storage"))
    }
}

/// An answer that keeps coming until the test finishes it.
@MainActor
private final class HeldStream {
    var continuation: AsyncThrowingStream<StreamOutput, Error>.Continuation?

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        let (stream, continuation) = AsyncThrowingStream<StreamOutput, Error>.makeStream()
        continuation.yield(.text("Half"))
        self.continuation = continuation
        return stream
    }
}
