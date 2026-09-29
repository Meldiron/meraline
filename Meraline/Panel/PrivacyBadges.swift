import SwiftUI

/// A quiet mark beside the mode toggle: a crossed-out eye while the window asks to stay out of screen sharing
/// (`Preferences.hidesFromScreenSharing`). Plain secondary, without glass or pink, since it tells rather than does.
struct PrivacyBadges: View {
    let preferences: Preferences

    var body: some View {
        HStack(spacing: 10) {
            if preferences.hidesFromScreenSharing {
                Image(systemName: "eye.slash")
                    .hoverTip("Hidden from screen sharing, in the apps that allow it")
                    .accessibilityLabel("Hidden from screen sharing")
                    .transition(.opacity)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .animation(.smooth(duration: 0.2), value: preferences.hidesFromScreenSharing)
    }
}
