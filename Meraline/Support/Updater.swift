import AppKit
import Observation
import Sparkle

/// Sparkle, wrapped for the menu bar and Settings. It starts only when Info.plist carries both the
/// feed URL and the public key, so a build without them simply has no updater.
///
/// Updates download and install silently by default (SUAutomaticallyUpdate). What Sparkle finds or
/// stages is exposed as `state`, so the menu bar item and the Software Update pane can offer it,
/// and the notes of an update are kept so "What's new" can show them after it is installed.
@Observable
final class Updater: NSObject {
    struct Update: Equatable {
        let version: String
        /// Release notes as Markdown, or nil when the appcast item carried none.
        let notes: String?

        init(version: String, notes: String?) {
            self.version = version
            self.notes = notes
        }

        init(_ item: SUAppcastItem) {
            version = item.displayVersionString
            if let description = item.itemDescription, !description.trimmed.isEmpty {
                notes = item.itemDescriptionFormat == "html" ? ReleaseNotes.strippingHTML(description) : description
            } else {
                notes = nil
            }
        }
    }

    enum State: Equatable {
        case idle
        /// Found by a check; Sparkle shows it when asked.
        case available(Update)
        /// Downloaded and ready; it installs on quit, or right away on request.
        case staged(Update)

        var description: String {
            switch self {
            case .idle: "up to date"
            case .available(let update): "\(update.version) available"
            case .staged(let update): "\(update.version) staged"
            }
        }
    }

    private static let pendingVersionKey = "whatsNew.version"
    private static let pendingNotesKey = "whatsNew.notes"

    private(set) var canCheckForUpdates = false
    private(set) var lastCheck: Date?
    private(set) var state = State.idle

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var installNow: (() -> Void)?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let defaults: UserDefaults

    var isAvailable: Bool { controller != nil }

    var availableUpdate: Update? {
        if case .available(let update) = state { update } else { nil }
    }

    var stagedUpdate: Update? {
        if case .staged(let update) = state { update } else { nil }
    }

    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
            Log.updates.info("Automatic checks \(newValue ? "on" : "off")")
        }
    }

    var downloadsAutomatically: Bool {
        get {
            access(keyPath: \.downloadsAutomatically)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
        }
        set {
            withMutation(keyPath: \.downloadsAutomatically) {
                controller?.updater.automaticallyDownloadsUpdates = newValue
            }
            Log.updates.info("Automatic install \(newValue ? "on" : "off")")
        }
    }

    /// Stable follows the feed in Info.plist; beta follows the rolling `beta` pre-release and
    /// accepts items tagged for the beta channel. Switching re-arms Sparkle's schedule.
    var channel: UpdateChannel {
        get {
            access(keyPath: \.channel)
            return preferences.updateChannel
        }
        set {
            guard newValue != preferences.updateChannel else { return }
            withMutation(keyPath: \.channel) {
                preferences.updateChannel = newValue
            }
            Log.updates.info("Update channel set to \(newValue.rawValue)")
            controller?.updater.resetUpdateCycleAfterShortDelay()
        }
    }

    var status: Diagnostics.UpdateStatus {
        Diagnostics.UpdateStatus(
            isAvailable: isAvailable,
            channel: channel,
            checksAutomatically: checksAutomatically,
            downloadsAutomatically: downloadsAutomatically,
            lastCheck: lastCheck,
            state: state.description
        )
    }

    init(preferences: Preferences, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.defaults = defaults
        super.init()

        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String)?.trimmed ?? ""
        let key = (info["SUPublicEDKey"] as? String)?.trimmed ?? ""
        guard !feed.isEmpty, !key.isEmpty else {
            Log.updates.info("Updates are off: no feed URL or public key in this build")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        lastCheck = controller.updater.lastUpdateCheckDate
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: .new) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            controller.updater.observe(\.lastUpdateCheckDate, options: .new) { [weak self] _, change in
                let value = change.newValue ?? nil
                Task { @MainActor in self?.lastCheck = value }
            }
        ]
        Log.updates.info("Updater started on the \(preferences.updateChannel.rawValue) channel")
    }

    /// Opens Sparkle's window: a check when nothing is known, the found update otherwise.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// Installs a staged update now and relaunches, instead of waiting for quit.
    func installStagedUpdate() {
        guard let installNow else {
            checkForUpdates()
            return
        }
        Log.updates.info("Installing the staged update now")
        installNow()
    }

    /// The notes of the update that produced the running version, if Sparkle installed it. Read
    /// once by the What's new window; a manual install has nothing stored.
    func takeWhatsNew(for currentVersion: String) -> Update? {
        guard defaults.string(forKey: Self.pendingVersionKey) == currentVersion else { return nil }
        let notes = defaults.string(forKey: Self.pendingNotesKey)
        defaults.removeObject(forKey: Self.pendingVersionKey)
        defaults.removeObject(forKey: Self.pendingNotesKey)
        return Update(version: currentVersion, notes: notes)
    }

    private func remember(_ update: Update) {
        defaults.set(update.version, forKey: Self.pendingVersionKey)
        defaults.set(update.notes, forKey: Self.pendingNotesKey)
    }
}

extension Updater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        switch preferences.updateChannel {
        case .stable: nil
        case .beta: Bundle.main.betaFeedURL
        }
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        preferences.updateChannel == .beta ? ["beta"] : []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let update = Update(item)
        remember(update)
        state = .available(update)
        Log.updates.info("Found \(update.version)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        state = .idle
        installNow = nil
        Log.updates.info("No update available")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let update = Update(item)
        remember(update)
        installNow = immediateInstallHandler
        state = .staged(update)
        Log.updates.info("Staged \(update.version); it installs on quit")
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        remember(Update(item))
        Log.updates.info("Installing \(item.displayVersionString)")
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip {
            self.state = .idle
            Log.updates.info("Skipped \(updateItem.displayVersionString)")
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Log.updates.error("Update aborted: \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            Log.updates.error("Update check failed: \(error.localizedDescription)")
        }
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself when it can take focus, right after launch for
    /// instance. Otherwise the menu bar item and the Software Update pane announce it, and the
    /// user opens it from there, so a background app never pops a window over other work.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { NSApp.activate() }
    }
}
