import AppKit
import Observation
import Sparkle

@Observable
final class Updater: NSObject {
    private(set) var canCheckForUpdates = false
    private(set) var lastCheck: Date?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    var isAvailable: Bool { controller != nil }

    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
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
        }
    }

    override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String)?.trimmed ?? ""
        let key = (info["SUPublicEDKey"] as? String)?.trimmed ?? ""
        guard !feed.isEmpty, !key.isEmpty else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
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
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate { NSApp.activate() }
    }
}
