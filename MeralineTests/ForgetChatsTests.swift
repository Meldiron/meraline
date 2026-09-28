import AppKit
import Foundation
import Testing
@testable import Meraline

/// Settings › General › Privacy: forgetting every chat when the Mac sleeps or its screen locks.
@MainActor
struct ForgetChatsTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.forget.\(UUID().uuidString)")

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @Test func forgettingOnSleepAndOnLockIsOffUntilTurnedOnAndThenKept() {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let noSecrets = SecretStore(read: { _ in "" }, write: { _, _ in })
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(!preferences.forgetsChatsOnSleep)
        #expect(!preferences.forgetsChatsOnLock)
        preferences.forgetsChatsOnLock = true
        let reloaded = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(!reloaded.forgetsChatsOnSleep)
        #expect(reloaded.forgetsChatsOnLock)
    }

    @Test func theMacSleepingOrLockingForgetsOnlyWhatSettingsSay() {
        let preferences = GameTestSupport.preferences()
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        var forgettings = 0
        let watcher = AwayWatcher(preferences: preferences, workspace: workspace, distributed: distributed) {
            forgettings += 1
            return 0
        }
        func sleep() { workspace.post(name: NSWorkspace.willSleepNotification, object: nil) }
        func displaySleep() { workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil) }
        func lock() { distributed.post(name: AwayWatcher.screenLocked, object: nil) }
        func switchUser() { workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil) }

        sleep(); displaySleep(); lock(); switchUser()
        #expect(forgettings == 0)

        preferences.forgetsChatsOnSleep = true
        lock(); switchUser()
        #expect(forgettings == 0)
        sleep(); displaySleep()
        #expect(forgettings == 2)

        preferences.forgetsChatsOnSleep = false
        preferences.forgetsChatsOnLock = true
        sleep(); displaySleep()
        #expect(forgettings == 2)
        lock(); switchUser()
        #expect(forgettings == 4)
        #expect(watcher.forgets(at: .lock))
        #expect(!watcher.forgets(at: .sleep))
    }

    @Test func forgettingTakesEveryChatWithItsWorkspaceAndWhatIsTyped() async throws {
        let model = ScriptedModel(["One", "Two"])
        let preferences = GameTestSupport.preferences(withProvider: false)
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.mode = .agent
        let session = ChatSession(preferences: preferences, workspaceRoot: root, usage: UsageLedger(file: nil)) { model.stream($0) }

        await GameTestSupport.play("First", in: session)
        let first = try #require(session.workspace).url
        session.reset()
        await GameTestSupport.play("Second", in: session)
        let second = try #require(session.workspace).url
        session.draft = "A third, half typed"
        session.bringCurrentSelection(text: SelectedText("Selected in Notes", appName: "Notes"), files: [])
        #expect(session.history.count == 1)
        #expect(session.offeredSelection != nil)

        #expect(session.forgetAll() == 2)
        #expect(session.turns.isEmpty)
        #expect(session.history.isEmpty)
        #expect(session.draft.isEmpty)
        #expect(session.offeredSelection == nil)
        #expect(session.workspace == nil)
        #expect(!exists(first))
        #expect(!exists(second))
        #expect(session.forgetAll() == 0)
        ChatWorkspace.removeAll(in: root)
    }

    @Test func forgettingStopsAnAnswerStillComing() async {
        let preferences = GameTestSupport.preferences()
        // An answer that never ends until it is stopped.
        let session = ChatSession(preferences: preferences, workspaceRoot: root, usage: UsageLedger(file: nil)) { _ in
            AsyncThrowingStream { $0.yield(.text("Half an ans")) }
        }
        session.draft = "Tell me a long story"
        session.send()
        for _ in 0..<100 where session.turns.last?.answer.isEmpty != false { await Task.yield() }
        #expect(session.isStreaming)
        #expect(session.forgetAll() == 1)
        #expect(!session.isStreaming)
        #expect(session.turns.isEmpty)
        for _ in 0..<20 { await Task.yield() }
        #expect(session.turns.isEmpty)
        #expect(session.history.isEmpty)
        ChatWorkspace.removeAll(in: root)
    }
}
