import AppKit
import SwiftUI
import Synchronization
import Testing
@testable import Meraline

/// The capsules under the card, in the app's own panel while it is hidden. On 2026-09-28 Sparkle staged an update
/// it had found while the window was hidden, and the capsule's change from Update Available to Restart to Update
/// hung the app for good: SwiftUI's key view loop never settled. The layouts here run under a watchdog, since a
/// hung main thread can't fail a test by itself.
@MainActor
struct AnnouncementsTests {
    private typealias Support = GameTestSupport

    private static func throwaway() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Runs `body`, then the run loop for the display cycle to lay the window out as the capsules animate, and
    /// ends the test run if that takes longer than `seconds`, since it would never end.
    private func settle(_ step: String = "", within seconds: UInt32 = 10, _ body: () -> Void) {
        let done = Mutex(false)
        let watchdog = Thread {
            sleep(seconds)
            guard !done.withLock({ $0 }) else { return }
            FileHandle.standardError.write(Data("AnnouncementsTests: the panel's layout never finished after \(step); ending the test run\n".utf8))
            exit(70)
        }
        FileHandle.standardError.write(Data("AnnouncementsTests: \(step)\n".utf8))
        watchdog.start()
        body()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        done.withLock { $0 = true }
    }

    @Test func aStagedUpdateTakesTheFoundOnesPlaceWithoutHangingTheHiddenPanel() {
        let defaults = Self.throwaway()
        defaults.set(true, forKey: ShortcutSetup.chosenKey) // the chat, not the shortcut picker
        let preferences = Support.preferences()
        let session = Support.session(ScriptedModel())
        let updater = Updater(preferences: preferences, defaults: defaults)
        #expect(!updater.isAvailable, "the test host never starts Sparkle; the state is pretended")
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: updater, updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        #expect(!controller.isVisible)
        settle("the panel is made") {}

        let update = Updater.Update(version: "9.9.9", notes: nil)
        settle("an update is found") { updater.pretend(.available(update)) }
        settle("the update is staged") { updater.pretend(.staged(update)) }
        settle("the update is found again") { updater.pretend(.available(update)) }
        settle("there is no update") { updater.pretend(.idle) }
        #expect(!controller.isVisible)
    }
}
