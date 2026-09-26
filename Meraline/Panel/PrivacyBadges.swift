import SwiftUI

/// Quiet words beside the mode toggle about where a chat can go: "on this Mac" while the provider that answers
/// runs here (`Preferences.answersOnThisMac`), and a crossed-out eye while the window asks to stay out of screen
/// sharing (`Preferences.hidesFromScreenSharing`). Plain secondary text, without glass or pink, since they tell
/// rather than do. When the row is short of room, as while the games are out, the words give way to their symbol.
struct PrivacyBadges: View {
    let preferences: Preferences

    var body: some View {
        HStack(spacing: 10) {
            if preferences.answersOnThisMac {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.laptopcomputer")
                        Text("on this Mac")
                    }
                    Image(systemName: "lock.laptopcomputer")
                }
                .help("\(preferences.activeProvider?.name ?? "The model") answers on this Mac. Nothing you ask leaves it.")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Answers on this Mac")
                .transition(.opacity)
            }
            if preferences.hidesFromScreenSharing {
                Image(systemName: "eye.slash")
                    .help("Hidden from screen sharing, in the apps that allow it")
                    .accessibilityLabel("Hidden from screen sharing")
                    .transition(.opacity)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .animation(.smooth(duration: 0.2), value: preferences.answersOnThisMac)
        .animation(.smooth(duration: 0.2), value: preferences.hidesFromScreenSharing)
    }
}
