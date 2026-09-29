import SwiftUI

/// Capsules under the card, at its left, as the buttons above it are at its top: Copy Diagnostics after a crash
/// (which also says Copied for a moment when the sparkle's panel copies them), What's New after an update, which opens the notes under the input, and an update Sparkle found or staged,
/// which opens Sparkle's window or restarts into it. Each cross hides its capsule until the next update, or the
/// next crash. Glass with the faint pink tint of the active pin, a little stronger while the notes are open.
struct Announcements: View {
    /// The capsules' height, like the circles above the card.
    static let size = ContextButtons.size
    /// From the card to the capsules, and from the capsules to the window's bottom.
    static let inset = ContextButtons.inset
    /// How much the row adds below the card, beyond the window's usual margin, while it shows.
    static let roomBelow: CGFloat = inset + size + inset - PanelController.margin

    let whatsNew: WhatsNew
    /// The update to offer, found or staged, if its capsule wasn't hidden (see `UpdateNotice`).
    let update: Updater.State?
    let openUpdate: () -> Void
    let hideUpdate: (Updater.Update) -> Void
    /// Offers the diagnostics once after a crash, and says Copied when they were (see `CrashNotice`).
    let crash: CrashNotice
    let copyDiagnostics: () -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                if crash.isOffered {
                    AnnouncementCapsule(
                        title: crash.isCopied ? "Copied" : "Copy Diagnostics",
                        symbol: crash.isCopied ? "checkmark" : "exclamationmark.triangle",
                        help: crash.isCopied
                            ? "Diagnostics copied, with no questions, answers, or keys in them, to paste into a bug report."
                            : "Meraline quit unexpectedly. Copy what went wrong, with no questions, answers, or keys in it, to paste into a bug report.",
                        dismissHelp: "Hide"
                    ) {
                        copyDiagnostics()
                    } dismiss: {
                        crash.dismiss()
                    }
                    .transition(.opacity)
                }
                if let notes = whatsNew.update {
                    AnnouncementCapsule(
                        title: "What’s New",
                        symbol: "sparkles",
                        help: whatsNew.isExpanded ? "Hide the notes" : "What’s new in Meraline \(notes.version)",
                        isActive: whatsNew.isExpanded
                    ) {
                        whatsNew.isExpanded.toggle()
                    } dismiss: {
                        whatsNew.dismiss()
                    }
                    .transition(.opacity)
                }
                if let update {
                    updateCapsule(update)
                        .transition(.opacity)
                }
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .animation(.smooth(duration: 0.2), value: whatsNew.update)
        .animation(.smooth(duration: 0.2), value: update)
        .animation(.smooth(duration: 0.2), value: crash.isOffered)
        .animation(.smooth(duration: 0.2), value: crash.isCopied)
    }

    /// One capsule for the update found and for it staged, whose label changes, never one capsule for each.
    /// Two of them cross-fading, when Sparkle staged the update it had found while the window was hidden, hung
    /// Meraline for good on macOS 27: two focusable buttons lay on the same spot, and SwiftUI never finished
    /// rebuilding its key view loop (see `AnnouncementsTests`).
    @ViewBuilder
    private func updateCapsule(_ state: Updater.State) -> some View {
        if let update = state.update {
            AnnouncementCapsule(
                title: state.isStaged ? "Restart to Update" : "Update Available",
                symbol: state.isStaged ? "arrow.down.circle.fill" : "arrow.down.circle",
                help: state.isStaged
                    ? "Meraline \(update.version) is ready. Restart now to install it, or it installs when you quit."
                    : "Update to Meraline \(update.version)"
            ) {
                openUpdate()
            } dismiss: {
                hideUpdate(update)
            }
        }
    }
}

/// A capsule with a label that does its part and a cross that hides it.
private struct AnnouncementCapsule: View {
    let title: String
    let symbol: String
    let help: String
    var dismissHelp = "Hide until the next update"
    var isActive = false
    let action: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .foregroundStyle(Color.meralinePink)
                    Text(title)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .help(help)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .help(dismissHelp)
            .accessibilityLabel("Dismiss \(title)")
        }
        .buttonStyle(.plain)
        .frame(height: Announcements.size)
        .glassEffect(.regular.tint(.meralinePink.opacity(isActive ? 0.22 : 0.12)).interactive(), in: .capsule)
    }
}
