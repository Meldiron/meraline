import AppKit

/// Notices the Mac being left: it or its display going to sleep, or its screen locking, which switching to another
/// user does too. When Settings › General › Privacy says so (`Preferences.forgetsChatsOnSleep`, `forgetsChatsOnLock`),
/// `forget` runs and every chat goes (`PanelController.forgetChats()`). Shutting down, restarting, and logging out
/// quit Meraline, which forgets them anyway.
final class AwayWatcher {
    /// How the Mac was left.
    enum Moment: String {
        case sleep
        case lock
    }

    /// What macOS posts to every app as the screen locks. NSWorkspace has no notification of its own for it.
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")

    private let preferences: Preferences
    /// Forgets every chat, and says how many went.
    private let forget: () -> Int

    /// `workspace` and `distributed` are for tests, which post to centers of their own rather than to every app.
    init(
        preferences: Preferences,
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributed: NotificationCenter = DistributedNotificationCenter.default(),
        forget: @escaping () -> Int
    ) {
        self.preferences = preferences
        self.forget = forget
        let moments: [(NotificationCenter, Notification.Name, Moment)] = [
            (workspace, NSWorkspace.willSleepNotification, .sleep),
            (workspace, NSWorkspace.screensDidSleepNotification, .sleep),
            (distributed, Self.screenLocked, .lock),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .lock),
        ]
        for (center, name, moment) in moments {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.left(at: moment) }
            }
        }
    }

    /// Whether Settings says to forget every chat when the Mac is left this way.
    func forgets(at moment: Moment) -> Bool {
        switch moment {
        case .sleep: preferences.forgetsChatsOnSleep
        case .lock: preferences.forgetsChatsOnLock
        }
    }

    private func left(at moment: Moment) {
        guard forgets(at: moment) else { return }
        let forgot = forget()
        Log.chat.info("\(moment == .sleep ? "The Mac went to sleep" : "The screen locked"): \(forgot) chat(s) forgotten")
    }
}
