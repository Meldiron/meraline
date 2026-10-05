import Foundation
import Testing
@testable import Meraline

/// A shake of the window forgets Recent Chats without asking, so for a few seconds they can come back
/// (`ChatSession.shakeAwayHistory()`). Until 2026-10-06 they were gone at once.
@MainActor
struct ShakeUndoTests {
    private typealias Support = GameTestSupport
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.shake.\(UUID().uuidString)")

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// A session with `count` chats in Recent Chats, each with a workspace, holding them for `window` after a shake.
    private func sessionWithChats(_ count: Int, window: Duration = .seconds(60)) async throws -> (session: ChatSession, folders: [URL]) {
        let preferences = Support.preferences()
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "claude", apiKey: "", isEnabled: true)
        preferences.mode = .agent
        let model = ScriptedModel(Array(repeating: "Ok", count: count + 1))
        let session = ChatSession(preferences: preferences, workspaceRoot: root) { model.stream($0) }
        session.shakeUndoWindow = window
        var folders: [URL] = []
        for index in 1...count {
            await Support.play("Question \(index)", in: session)
            folders.append(try #require(session.workspace).url)
            session.reset()
        }
        #expect(session.history.count == count)
        return (session, folders)
    }

    @Test func undoPutsTheShakenChatsBackAsTheyWere() async throws {
        let (session, folders) = try await sessionWithChats(3)
        let before = session.history
        #expect(session.shakeAwayHistory() == 3)
        #expect(session.history.isEmpty, "held chats count nowhere")
        #expect(session.canTakeBackShakenChats)
        #expect(folders.allSatisfy(exists), "their workspaces wait with them")

        // A chat archived meanwhile stays on top when they come back.
        await Support.play("Meanwhile", in: session)
        session.reset()
        #expect(session.takeBackShakenChats() == 3)
        #expect(!session.canTakeBackShakenChats)
        #expect(session.history.count == 4)
        #expect(Array(session.history.dropFirst()) == before, "order, time left, and workspaces as they were")
        #expect(session.history.first?.title == "Meanwhile")
        #expect(folders.allSatisfy(exists))
        ChatWorkspace.removeAll(in: root)
    }

    @Test func afterTheWindowTheChatsAndTheirWorkspacesAreGone() async throws {
        let (session, folders) = try await sessionWithChats(2, window: .milliseconds(30))
        #expect(session.shakeAwayHistory() == 2)
        for _ in 0..<100 where session.canTakeBackShakenChats { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!session.canTakeBackShakenChats)
        #expect(session.takeBackShakenChats() == 0, "too late")
        #expect(session.history.isEmpty)
        #expect(!folders.contains(where: exists))
        ChatWorkspace.removeAll(in: root)
    }

    @Test func aSecondShakeAndForgettingEverythingDropTheHeldChats() async throws {
        let (session, folders) = try await sessionWithChats(2)
        #expect(session.shakeAwayHistory() == 2)
        await Support.play("One more", in: session)
        session.reset()
        #expect(session.shakeAwayHistory() == 1, "the chat since; the two held before go for good")
        #expect(!folders.contains(where: exists))
        #expect(session.takeBackShakenChats() == 1, "the second shake's chat comes back")
        #expect(session.history.count == 1)

        #expect(session.shakeAwayHistory() == 1)
        #expect(session.forgetAll() == 0, "nothing open")
        #expect(!session.canTakeBackShakenChats, "forgetting everything forgets the held chats too")
        ChatWorkspace.removeAll(in: root)
    }

    @Test func aChatWhoseTimeRanOutWhileHeldStaysGone() async throws {
        let (session, folders) = try await sessionWithChats(2)
        #expect(session.shakeAwayHistory() == 2)
        let later = Date.now.addingTimeInterval(ChatSession.chatLifetime + 60)
        #expect(session.takeBackShakenChats(now: later) == 0)
        #expect(session.history.isEmpty)
        #expect(!folders.contains(where: exists))
        ChatWorkspace.removeAll(in: root)
    }

    @Test func clearRecentChatsKeepsNoUndo() async throws {
        let (session, folders) = try await sessionWithChats(2)
        #expect(session.forgetHistory() == 2)
        #expect(!session.canTakeBackShakenChats)
        #expect(!folders.contains(where: exists))
        ChatWorkspace.removeAll(in: root)
    }
}
