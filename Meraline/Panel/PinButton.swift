import SwiftUI

/// The pin, which keeps the window open when you click elsewhere (⌘P).
struct PinButton: View {
    let preferences: Preferences

    var body: some View {
        let isPinned = preferences.isPinned
        Button { preferences.isPinned.toggle() } label: {
            // The symbol turns, never the glass around it.
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isPinned ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .rotationEffect(.degrees(45))
                .frame(width: 32, height: 32)
                .contentTransition(.symbolEffect(.replace))
                .glassEffect(isPinned ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("p")
        .hoverTip(isPinned ? "Unpin: close when clicking elsewhere (⌘P)" : "Pin: stay open when clicking elsewhere (⌘P)", edge: .bottom)
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
    }
}
