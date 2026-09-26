import Foundation
import Testing
@testable import Meraline

@MainActor
struct UpdateNoticeTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func offersAFoundOrStagedUpdate() {
        let notice = UpdateNotice(defaults: makeDefaults())
        let update = Updater.Update(version: "1.5.0", notes: nil)
        #expect(notice.offer(for: .idle) == nil)
        #expect(notice.offer(for: .available(update)) == .available(update))
        #expect(notice.offer(for: .staged(update)) == .staged(update))
    }

    @Test func hidingLastsUntilANewerUpdate() {
        let defaults = makeDefaults()
        let update = Updater.Update(version: "1.5.0", notes: nil)
        UpdateNotice(defaults: defaults).hide(update)

        let relaunched = UpdateNotice(defaults: defaults)
        #expect(relaunched.offer(for: .available(update)) == nil)
        // Staging the same version after hiding it found keeps it hidden.
        #expect(relaunched.offer(for: .staged(update)) == nil)

        let next = Updater.Update(version: "1.5.1", notes: nil)
        #expect(relaunched.offer(for: .available(next)) == .available(next))
    }
}
