import AppKit
import Observation

/// After Meraline quits unexpectedly, the next launch offers its diagnostics once: a capsule under the card copies
/// them, with the crash macOS reported, and goes away, as its cross makes it go. Only the launch date stays in
/// UserDefaults, to tell a crash since the previous launch from an older one; the crash itself is read from macOS's
/// report and kept in memory, so Settings › About › Copy Diagnostics includes it for the rest of this run.
///
/// The sparkle's panel copies the same diagnostics at any time, crash or not, and the same capsule shows for a
/// moment to say Copied: one capsule whose label changes, never a second one beside or over it.
@Observable
final class CrashNotice {
    static let shared = CrashNotice()
    private static let lastLaunchKey = "crashNotice.lastLaunch"
    /// How long the capsule says Copied before it goes.
    static let copiedFor: Duration = .seconds(1.5)

    /// The crash that ended a run since the previous launch, if macOS reported one.
    private(set) var crash: CrashReport?
    /// Whether the capsule under the card shows: offering the diagnostics after a crash, or saying they were copied.
    private(set) var isOffered = false
    /// Whether the diagnostics were just copied, for the capsule's checkmark before it goes.
    private(set) var isCopied = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let folders: [URL]
    @ObservationIgnored private let pasteboard: NSPasteboard
    /// Takes the capsule away once it has said Copied, started over by each copy.
    @ObservationIgnored private var hiding: Task<Void, Never>?

    init(defaults: UserDefaults = .meraline, folders: [URL] = CrashReport.folders, pasteboard: NSPasteboard = .general) {
        self.defaults = defaults
        self.folders = folders
        self.pasteboard = pasteboard
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

    /// Copies the diagnostics as they are now, with the crash if there was one, for the capsule after a crash and
    /// the sparkle's panel alike.
    func copyDiagnostics(of session: ChatSession, preferences: Preferences, updates: Diagnostics.UpdateStatus) async {
        let storage = await Diagnostics.storage(of: session)
        copy(Diagnostics.report(preferences: preferences, updates: updates, crash: crash, storage: storage))
    }

    /// Copies the report, says so for a moment in the capsule, showing it if it was not, and takes it away.
    func copy(_ report: String) {
        Diagnostics.copyToPasteboard(report, to: pasteboard)
        Log.app.info(isOffered && !isCopied ? "Diagnostics copied after a crash" : "Diagnostics copied from the panel")
        isOffered = true
        isCopied = true
        hiding?.cancel()
        hiding = Task { [weak self] in
            try? await Task.sleep(for: Self.copiedFor)
            guard !Task.isCancelled else { return }
            self?.isOffered = false
        }
    }

    func dismiss() {
        isOffered = false
        Log.app.info("Crash diagnostics capsule hidden")
    }
}
