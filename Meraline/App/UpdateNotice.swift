import Foundation
import Observation

/// Whether the capsule under the card offers the update Sparkle found or staged. Its cross hides that
/// version, and only a newer one brings the capsule back. The hidden version stays in UserDefaults, so
/// the capsule stays away across launches; the menu bar item and Settings offer the update regardless.
@Observable
final class UpdateNotice {
    private static let hiddenVersionKey = "updateNotice.hiddenVersion"

    /// The version whose capsule was put away, if any.
    private(set) var hiddenVersion: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .meraline) {
        self.defaults = defaults
        hiddenVersion = defaults.string(forKey: Self.hiddenVersionKey)
    }

    /// What the capsule offers for the updater's state: the update, found or staged, unless its version
    /// was hidden.
    func offer(for state: Updater.State) -> Updater.State? {
        switch state {
        case .idle: nil
        case .available(let update), .staged(let update): update.version == hiddenVersion ? nil : state
        }
    }

    /// Hides the capsule until an update newer than this one comes.
    func hide(_ update: Updater.Update) {
        hiddenVersion = update.version
        defaults.set(update.version, forKey: Self.hiddenVersionKey)
        Log.updates.info("Update capsule hidden for \(update.version)")
    }
}
