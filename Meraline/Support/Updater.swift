import AppKit
import Observation
import Sparkle

/// Sparkle, wrapped for the menu bar and Settings. It starts only when Info.plist carries both the
/// feed URL and the public key, so a build without them simply has no updater.
///
/// Updates download and install silently by default (SUAutomaticallyUpdate). What Sparkle finds or
/// stages is exposed as `state`, so the menu bar item and the Software Update pane can offer it,
/// and the notes of an update are kept so the panel's What's New can show them after it is installed.
///
/// Meraline checks every `checkInterval` (15 minutes): a timer of its own while it runs, and the window's opening
/// for a Mac that slept through it, both through `checkIfDue`, so an update is on its capsule when ⌥ Space shows
/// the window. Sparkle's own schedule (`SUScheduledCheckInterval` in project.yml) goes no lower than an hour, so
/// it stays at that, a floor under Meraline's.
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

        /// The update found or staged, if any.
        var update: Update? {
            switch self {
            case .idle: nil
            case .available(let update), .staged(let update): update
            }
        }

        var isStaged: Bool {
            if case .staged = self { true } else { false }
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

    /// The version running, as its GitHub release is tagged without the `v`: 1.7.0, or 1.8.0-beta.1.
    let currentVersion: String

    var isAvailable: Bool { controller != nil || isStandIn }

    /// The channel the running build was released on, whichever the updater follows now.
    var currentChannel: UpdateChannel { UpdateChannel(version: currentVersion) }

    /// A beta is running on the stable channel. Sparkle never goes back a version, so the beta stays until a
    /// stable release newer than it comes out.
    var isLeavingBeta: Bool { channel == .stable && currentChannel == .beta }

    #if DEBUG
    /// For tests: what Sparkle's delegate calls would have reported.
    func pretend(_ state: State) {
        self.state = state
    }

    /// For pictures of Settings › Software Update: an updater set up as a release build's is, checking and
    /// installing by itself, though the test host never starts Sparkle.
    func pretendAvailable(lastCheck: Date?) {
        pretendsAvailable = true
        canCheckForUpdates = true
        self.lastCheck = lastCheck
    }

    @ObservationIgnored private var pretendsAvailable = false
    private var isStandIn: Bool { pretendsAvailable }
    #else
    private var isStandIn: Bool { false }
    #endif

    var availableUpdate: Update? {
        if case .available(let update) = state { update } else { nil }
    }

    var stagedUpdate: Update? {
        if case .staged(let update) = state { update } else { nil }
    }

    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? isStandIn
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
            return controller?.updater.automaticallyDownloadsUpdates ?? isStandIn
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

    init(preferences: Preferences, defaults: UserDefaults = .meraline, currentVersion: String = Bundle.main.shortVersion) {
        self.preferences = preferences
        self.defaults = defaults
        self.currentVersion = currentVersion
        super.init()

        // The test host never checks for updates, as it never starts the app: a test's updater only pretends.
        guard !MeralineApp.isHostingTests else { return }
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
        keepChecking()
    }

    /// How old a check is before another runs, from the timer or the window's opening: a quarter of an hour, under
    /// Sparkle's floor of an hour for a schedule of its own, which is why Meraline keeps the schedule itself.
    static let checkInterval: TimeInterval = 15 * 60

    /// Whether a check should run: the updater runs, checks by itself, and is free to, and there was no check yet
    /// or the last is `checkInterval` old. Sparkle stamps the date as a check starts, so a Mac that is offline is
    /// asked again after the interval, not at every tick or opening.
    func isCheckDue(at now: Date = .now) -> Bool {
        guard isAvailable, checksAutomatically, canCheckForUpdates else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Self.checkInterval
    }

    /// Checks in the background when a check is due: every `checkInterval` while Meraline runs, and as the window
    /// opens, for a Mac that slept through the timer, so an update that came out meanwhile shows on its capsule
    /// now. Nothing opens: the update downloads and stages, or waits on the capsule, as one of Sparkle's own
    /// scheduled checks does. Says whether it checked.
    @discardableResult
    func checkIfDue(at now: Date = .now) -> Bool {
        guard isCheckDue(at: now) else { return false }
        let age = lastCheck.map { "\(Int(now.timeIntervalSince($0) / 60)) min ago" } ?? "never"
        Log.updates.info("Checking for updates in the background; last check \(age)")
        controller?.updater.checkForUpdatesInBackground()
        return true
    }

    /// Asks `checkIfDue` every `checkInterval` while Meraline runs. The continuous clock counts the Mac's sleep,
    /// so a tick slept through comes as it wakes.
    private func keepChecking() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.checkInterval))
                guard let self else { return }
                checkIfDue()
            }
        }
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
    /// once at the first launch after the update, which hands them to `WhatsNew`; a manual install
    /// has nothing stored.
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

extension UpdateChannel {
    /// The channel `version` went out on, read as the release pipeline reads its tag: a version with a
    /// pre-release suffix (1.8.0-beta.1, 1.8.0-rc.1) is a beta, and its GitHub release is a pre-release.
    init(version: String) {
        self = version.contains("-") ? .beta : .stable
    }

    var symbol: String {
        switch self {
        case .stable: "checkmark.seal"
        case .beta: "flask"
        }
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
