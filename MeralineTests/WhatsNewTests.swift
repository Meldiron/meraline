import Foundation
import Testing
@testable import Meraline

@MainActor
struct WhatsNewTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func nothingToAnnounceAtFirst() {
        #expect(WhatsNew(defaults: makeDefaults(), currentVersion: "1.3.0").update == nil)
    }

    @Test func anAnnouncementOutlastsARelaunch() {
        let defaults = makeDefaults()
        let update = Updater.Update(version: "1.3.0", notes: "- **Games** have buttons")
        WhatsNew(defaults: defaults, currentVersion: "1.3.0").announce(update)
        #expect(WhatsNew(defaults: defaults, currentVersion: "1.3.0").update == update)
    }

    @Test func dismissingHidesItUntilTheNextUpdate() {
        let defaults = makeDefaults()
        let whatsNew = WhatsNew(defaults: defaults, currentVersion: "1.3.0")
        whatsNew.announce(Updater.Update(version: "1.3.0", notes: nil))
        whatsNew.isExpanded = true
        whatsNew.dismiss()
        #expect(whatsNew.update == nil)
        #expect(!whatsNew.isExpanded)
        #expect(WhatsNew(defaults: defaults, currentVersion: "1.3.0").update == nil)

        let next = Updater.Update(version: "1.4.0", notes: "- More")
        WhatsNew(defaults: defaults, currentVersion: "1.4.0").announce(next)
        #expect(WhatsNew(defaults: defaults, currentVersion: "1.4.0").update == next)
    }

    @Test func anAnnouncementForAnotherVersionIsNotShown() {
        let defaults = makeDefaults()
        WhatsNew(defaults: defaults, currentVersion: "1.3.0").announce(Updater.Update(version: "1.3.0", notes: nil))
        #expect(WhatsNew(defaults: defaults, currentVersion: "1.3.1").update == nil)
    }
}
