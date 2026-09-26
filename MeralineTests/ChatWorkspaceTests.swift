import Foundation
import Testing
@testable import Meraline

@MainActor
struct ChatWorkspaceTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.workspaces.\(UUID().uuidString)")

    private func exists(_ url: URL?) -> Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// A session whose only ready provider is an agent, so every question goes to one.
    private func agentSession(_ model: ScriptedModel) -> ChatSession {
        let preferences = GameTestSupport.preferences(withProvider: false)
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.mode = .agent
        return ChatSession(preferences: preferences, workspaceRoot: root) { model.stream($0) }
    }

    @Test func aWorkspaceIsAnEmptyFolderUntilRemoved() throws {
        let workspace = try ChatWorkspace.make(in: root)
        #expect(exists(workspace.url))
        #expect(try FileManager.default.contentsOfDirectory(atPath: workspace.url.path).isEmpty)
        workspace.remove()
        #expect(!exists(workspace.url))
        _ = try ChatWorkspace.make(in: root)
        ChatWorkspace.removeAll(in: root)
        #expect(!exists(root))
    }

    @Test func staleWorkspacesOfGoneProcessesAreRemovedAtLaunch() throws {
        let parent = root.appending(path: "parent")
        let mine = parent.appending(path: String(ProcessInfo.processInfo.processIdentifier))
        let gone = parent.appending(path: "2147483000")
        let notAPid = parent.appending(path: "notes")
        for folder in [mine, gone, notAPid] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        ChatWorkspace.removeStale(in: parent)
        #expect(exists(mine))
        #expect(!exists(gone))
        #expect(exists(notAPid))
        #expect(ChatWorkspace.defaultRoot.lastPathComponent == String(ProcessInfo.processInfo.processIdentifier))
        ChatWorkspace.removeAll(in: root)
    }

    @Test func anAgentGetsOneWorkspacePerChat() async throws {
        let model = ScriptedModel(["One"])
        let session = agentSession(model)
        #expect(session.workspace == nil)
        let first = session.makeRequest(asking: "Hi", images: [], of: .claudeCode)
        let workspace = try #require(session.workspace)
        #expect(first.workspace == workspace.url)
        #expect(exists(workspace.url))
        #expect(session.makeRequest(asking: "Again", images: [], of: .claudeCode).workspace == workspace.url)
        #expect(session.makeRequest(asking: "Hi", images: [], of: .custom).workspace == nil)

        // Nothing was answered, so a new chat drops the folder.
        session.reset()
        #expect(session.workspace == nil)
        #expect(!exists(workspace.url))

        // An answered chat takes its folder along to Recent Chats and brings it back.
        await GameTestSupport.play("Hi", in: session)
        let kept = try #require(session.workspace)
        #expect(model.requests.last?.workspace == kept.url)
        session.reset()
        #expect(session.workspace == nil)
        #expect(exists(kept.url))
        #expect(session.history.first?.workspace == kept)
        let id = try #require(session.history.first?.id)
        session.reopen(id)
        #expect(session.workspace == kept)
        #expect(session.history.isEmpty)
        ChatWorkspace.removeAll(in: root)
    }

    @Test func forgettingTheRecentChatsRemovesTheirWorkspaces() async throws {
        let model = ScriptedModel(["One", "Two"])
        let session = agentSession(model)
        await GameTestSupport.play("First", in: session)
        let first = try #require(session.workspace).url
        session.reset()
        await GameTestSupport.play("Second", in: session)
        let second = try #require(session.workspace).url
        #expect(session.forgetHistory() == 1)
        #expect(session.history.isEmpty)
        // The open chat keeps its own folder.
        #expect(!exists(first))
        #expect(exists(second))
        #expect(session.workspace?.url == second)
        ChatWorkspace.removeAll(in: root)
    }

    @Test func workspacesLeaveWithTheirChats() async throws {
        let model = ScriptedModel(Array(repeating: "Ok", count: 7))
        let session = agentSession(model)
        var folders: [URL] = []
        for index in 1...7 {
            await GameTestSupport.play("Question \(index)", in: session)
            folders.append(try #require(session.workspace).url)
            session.reset()
        }
        #expect(session.history.count == ChatSession.historyLimit)
        #expect(!exists(folders[0]))
        #expect(!exists(folders[1]))
        #expect(folders[2...].allSatisfy(exists))
        ChatWorkspace.removeAll(in: root)
    }
}
