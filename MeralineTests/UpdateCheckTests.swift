import Foundation
import Testing
@testable import Meraline

@MainActor
struct UpdateCheckTests {
    private let noSecrets = SecretStore(read: { _ in "" }, write: { _, _ in })

    private func makeUpdater() -> Updater {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Updater(preferences: Preferences(defaults: defaults, secrets: noSecrets), defaults: defaults, currentVersion: "1.13.0")
    }

    @Test func aCheckRunsOnceTheLastIsAQuarterOfAnHourOld() {
        let updater = makeUpdater()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        // A build without Sparkle (no feed, or the test host) never checks.
        #expect(!updater.isCheckDue(at: now))
        #expect(!updater.checkIfDue(at: now))

        // Meraline's own quarter of an hour, under Sparkle's floor; the "15 hours ago" of a daily check is long overdue.
        updater.pretendAvailable(lastCheck: now.addingTimeInterval(-15 * 60 * 60))
        #expect(Updater.checkInterval == 15 * 60)
        #expect(updater.checkIfDue(at: now))

        // A tick or an opening within the quarter asks nothing more of the feed.
        updater.pretendAvailable(lastCheck: now.addingTimeInterval(-14 * 60))
        #expect(!updater.isCheckDue(at: now))
        #expect(!updater.checkIfDue(at: now))

        updater.pretendAvailable(lastCheck: now.addingTimeInterval(-15 * 60))
        #expect(updater.isCheckDue(at: now))

        // Never checked counts as due.
        updater.pretendAvailable(lastCheck: nil)
        #expect(updater.isCheckDue(at: now))
    }
}
