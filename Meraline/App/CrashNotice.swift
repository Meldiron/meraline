import Foundation
import Observation

/// After Meraline quits unexpectedly, the next launch offers its diagnostics once: a capsule under the card copies
/// them, with the crash macOS reported, and goes away, as its cross makes it go. Only the launch date stays in
/// UserDefaults, to tell a crash since the previous launch from an older one; the crash itself is read from macOS's
/// report and kept in memory, so Settings › About › Copy Diagnostics includes it for the rest of this run.
@Observable
final class CrashNotice {
    static let shared = CrashNotice()
    private static let lastLaunchKey = "crashNotice.lastLaunch"
    /// How long the capsule says Copied before it goes.
    static let copiedFor: Duration = .seconds(1.5)

    /// The crash that ended a run since the previous launch, if macOS reported one.
    private(set) var crash: CrashReport?
    /// Whether the capsule under the card offers to copy the diagnostics.
    private(set) var isOffered = false
    /// Whether the capsule just copied them, for its checkmark before it goes.
    private(set) var isCopied = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let folders: [URL]

    init(defaults: UserDefaults = .meraline, folders: [URL] = CrashReport.folders) {
        self.defaults = defaults
        self.folders = folders
    }

    /// At launch: looks for a report of Meraline crashing since the previous launch, and remembers this one, so the
    /// same crash is never offered twice. The first launch has nothing to compare with and offers nothing.
    func checkForCrash(now: Date = .now) {
        let previousLaunch = defaults.object(forKey: Self.lastLaunchKey) as? Date
        defaults.set(now, forKey: Self.lastLaunchKey)
        guard let previousLaunch, let crash = CrashReport.latest(in: folders, since: previousLaunch) else { return }
        self.crash = crash
        isOffered = true
        Log.app.info("Meraline \(crash.version) (\(crash.build)) quit unexpectedly since the previous launch\(crash.exception.map { ", \($0)" } ?? ""); offering diagnostics")
    }

    /// Copies the diagnostics, says so for a moment, and takes the capsule away.
    func copy(_ report: String) {
        Diagnostics.copyToPasteboard(report)
        Log.app.info("Diagnostics copied after a crash")
        isCopied = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.copiedFor)
            self?.isOffered = false
        }
    }

    func dismiss() {
        isOffered = false
        Log.app.info("Crash diagnostics capsule hidden")
    }
}
