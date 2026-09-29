import KeyboardShortcuts
import SwiftUI

/// Settings › Permissions: everything Meraline may ask macOS for, in one place. Each permission says what it
/// turns on, shows whether macOS allows it right now, asks for it (Allow…), and opens the page of System
/// Settings with its switch. The pane looks again every second while it is open, since System Settings
/// doesn't always announce a switch that moved.
struct PermissionsPane: View {
    let preferences: Preferences
    private let permissions = Permissions.shared

    var body: some View {
        Form {
            PaneHeader(pane: .permissions, summary: "Meraline works without these. Each one turns on a few features outside its window, and only you can switch it on, in System Settings.")

            ForEach(Permission.allCases) { permission in
                section(for: permission)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func section(for permission: Permission) -> some View {
        let isAllowed = permissions.isAllowed(permission)
        return Section {
            LabeledContent {
                HStack(spacing: 8) {
                    PermissionStatus(isAllowed: isAllowed)
                    if !isAllowed {
                        Button("Allow…") { permissions.request(permission) }
                            .hoverTip("Asks macOS again for this copy of Meraline, even if its switch already looks on")
                    }
                }
                .animation(.smooth(duration: 0.2), value: isAllowed)
            } label: {
                HStack(spacing: 10) {
                    SettingsIcon(symbol: permission.symbol, tint: .gray, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.title)
                            .font(.headline)
                        Text(permission.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(uses(of: permission)) { use in
                LabeledContent {
                    Text(use.note)
                        .foregroundStyle(.secondary)
                } label: {
                    Text(use.title)
                    Text(use.detail)
                }
            }

            LabeledContent {
                Button("Open System Settings") { permissions.openSystemSettings(for: permission) }
            } label: {
                Text("Meraline’s switch")
                Text("System Settings › Privacy & Security › \(permission.settingsName)")
            }
        } footer: {
            Text(permission.promise)
        }
    }

    /// The features a permission turns on, each with its shortcut.
    private func uses(of permission: Permission) -> [PermissionUse] {
        switch permission {
        case .accessibility:
            [
                PermissionUse(
                    title: "Bring the selection",
                    detail: "Press the shortcut and the text selected in the app in front waits behind the cursor button above the window. Files selected in Finder come along.",
                    note: preferences.bringsSelection ? shortcut : "Off in General"
                ),
                PermissionUse(
                    title: "Insert Answer",
                    detail: "Pastes the last answer at the cursor of the app in front. Without access, it only copies the answer.",
                    note: "⌘↵"
                ),
            ]
        case .screenRecording:
            [
                PermissionUse(
                    title: "Screenshot",
                    detail: "The screen button above the window attaches a picture of the screen the window is on, with Meraline’s own windows left out.",
                    note: "⇧⌘S"
                ),
            ]
        }
    }

    /// The window's shortcut as macOS shows it, such as ⌥ Space.
    private var shortcut: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? ""
    }
}

/// Allowed, in green, or not allowed.
struct PermissionStatus: View {
    let isAllowed: Bool

    var body: some View {
        if isAllowed {
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Not allowed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionUse: Identifiable {
    let title: String
    let detail: String
    let note: String

    var id: String { title }
}

private extension Permission {
    /// What macOS lets Meraline do, in a line.
    var summary: String {
        switch self {
        case .accessibility: "Reads what you select in other apps, and pastes answers into them."
        case .screenRecording: "Takes a picture of your screen when you click the screen button."
        }
    }

    /// What Meraline does and doesn't do with it.
    var promise: String {
        switch self {
        case .accessibility:
            "Meraline reads the selection only when you press the shortcut, and never in password fields or while secure input is on. Services › Ask Meraline brings the selection without Accessibility access."
        case .screenRecording:
            "Meraline never records video or audio. It takes one picture when you click, and the picture stays in memory with the chat. If macOS asks to quit and reopen Meraline after you switch it on, let it."
        }
    }
}
