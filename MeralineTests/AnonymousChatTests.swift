import Foundation
import Testing
@testable import Meraline

@MainActor
struct AnonymousChatTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.anonymous.\(UUID().uuidString)")

    private func exists(_ url: URL?) -> Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    @Test func anAnonymousChatSkipsRecentChats() async {
        let session = GameTestSupport.session(ScriptedModel(["Paris."]))
        session.isAnonymous = true
        await GameTestSupport.play("Capital of France?", in: session)
        #expect(session.turns.count == 1)
        session.reset()
        #expect(session.turns.isEmpty)
        #expect(session.history.isEmpty)
        #expect(session.isAnonymous)
    }

    @Test func theModeDecidesWhenTheChatEnds() async {
        let session = GameTestSupport.session(ScriptedModel(["One", "Two"]))
        await GameTestSupport.play("Kept?", in: session)
        session.isAnonymous = true
        session.reset()
        #expect(session.history.isEmpty)

        await GameTestSupport.play("Forgotten?", in: session)
        session.isAnonymous = false
        session.reset()
        #expect(session.history.map(\.title) == ["Forgotten?"])
    }

    @Test func earlierChatsStayInRecentChats() async {
        let session = GameTestSupport.session(ScriptedModel(["One", "Two"]))
        await GameTestSupport.play("First?", in: session)
        session.reset()
        session.isAnonymous = true
        await GameTestSupport.play("Secret?", in: session)
        session.reset()
        #expect(session.history.map(\.title) == ["First?"])
    }

    @Test func aReopenedChatIsForgottenWhenItEndsAnonymously() async throws {
        let session = GameTestSupport.session(ScriptedModel(["One"]))
        await GameTestSupport.play("First?", in: session)
        session.reset()
        let id = try #require(session.history.first?.id)
        session.isAnonymous = true
        session.reopen(id)
        #expect(session.turns.count == 1)
        session.reset()
        #expect(session.history.isEmpty)
    }

    @Test func anExpiredAnonymousChatIsForgottenButTheDraftStays() async {
        let session = GameTestSupport.session(ScriptedModel(["One"]))
        session.isAnonymous = true
        await GameTestSupport.play("Secret?", in: session)
        session.draft = "Half a thought"
        session.expire()
        #expect(session.turns.isEmpty)
        #expect(session.history.isEmpty)
        #expect(session.draft == "Half a thought")
    }

    @Test func anAnonymousAgentChatTakesItsWorkspaceAlong() async throws {
        let model = ScriptedModel(["Kept", "Secret"])
        let preferences = GameTestSupport.preferences(withProvider: false)
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.mode = .agent
        let session = ChatSession(preferences: preferences, workspaceRoot: root) { model.stream($0) }
        defer { ChatWorkspace.removeAll(in: root) }

        await GameTestSupport.play("Kept?", in: session)
        let kept = try #require(session.workspace)
        session.reset()

        session.isAnonymous = true
        await GameTestSupport.play("Secret?", in: session)
        let secret = try #require(session.workspace)
        session.reset()
        #expect(!exists(secret.url))
        #expect(exists(kept.url))
        #expect(session.history.map(\.workspace) == [kept])
    }
}
