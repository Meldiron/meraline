import AppKit

/// What Meraline may ask macOS for. Meraline works without any of it; each one turns on features that reach
/// outside its own window. Settings › Permissions lists them in one place: what each is for, whether macOS
/// allows it right now, a way to ask, and the page of System Settings that holds its switch.
enum Permission: String, CaseIterable, Identifiable {
    /// Reading the selection in the app in front, and Insert Answer's paste (see `SelectionAccess`).
    case accessibility
    /// The screen button's picture (see `ScreenCapture`).
    case screenRecording

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    /// The list's name under System Settings › Privacy & Security.
    var settingsName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen & System Audio Recording"
        }
    }

    /// The page of System Settings › Privacy & Security with Meraline's switch.
    var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }
}

/// Whether macOS allows each `Permission` right now. Accessibility is `SelectionAccess`'s, which System
/// Settings announces; Screen Recording is looked at on `refresh()`, which the Permissions pane calls every
/// second while it is open.
@Observable
final class Permissions {
    static let shared = Permissions()

    private(set) var allowsScreenRecording = ScreenCapture.hasAccess

    private init() {}

    func isAllowed(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: SelectionAccess.shared.isGranted
        case .screenRecording: allowsScreenRecording
        }
    }

    func refresh() {
        SelectionAccess.shared.refresh()
        let allowed = ScreenCapture.hasAccess
        guard allowed != allowsScreenRecording else { return }
        allowsScreenRecording = allowed
        Log.app.info("Screen Recording access \(allowed ? "granted" : "withdrawn")")
    }

    /// Shows the system's request, starting over for this copy of Meraline (see `SelectionAccess.request()`).
    func request(_ permission: Permission) {
        switch permission {
        case .accessibility: SelectionAccess.shared.request()
        case .screenRecording: ScreenCapture.requestAccess()
        }
    }

    func openSystemSettings(for permission: Permission) {
        Log.app.info("Opening System Settings for \(permission.title) access")
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
