import AppKit
import SwiftUI

/// What to ask next, under the last answer: two or three glass capsules, one under another, each a question
/// suggested on this Mac (see `FollowUps`). A click puts the question in the input without sending it, so it can be
/// changed first; a Shift-click asks it at once, and while Shift is down the capsule under the pointer shows an
/// arrow for it, as the presets above the card do. They show only while the input is empty and nothing streams.
/// They fade in, but go at once rather than fading out, so a new set never lies over the old one while it fades
/// (two buttons on one spot hung the hidden window, see `Announcements`).
struct FollowUpChips: View {
    let questions: [String]
    let choose: (_ question: String, _ sends: Bool) -> Void

    @State private var hovered: String?
    @State private var isShiftDown = false
    @State private var flagsMonitor: Any?

    static let transition: AnyTransition = .asymmetric(insertion: .opacity, removal: .identity)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(questions, id: \.self, content: chip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested follow-ups")
        .onAppear(perform: watchShift)
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
        }
    }

    private func chip(_ question: String) -> some View {
        let sends = isShiftDown && hovered == question
        return Button { click(question) } label: {
            HStack(spacing: 7) {
                Image(systemName: sends ? "arrow.up" : "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 14)
                Text(question)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isOver in
            if isOver {
                hovered = question
                isShiftDown = NSEvent.modifierFlags.contains(.shift)
            } else if hovered == question {
                hovered = nil
            }
        }
        .help("Put it in the input, or Shift-click to ask it now")
        .accessibilityLabel(question)
        .accessibilityHint("Puts the question in the input. Shift-click asks it.")
    }

    private func click(_ question: String) {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        choose(question, flags.contains(.shift))
    }

    /// Follows Shift while the window has the keyboard, for the arrow on the capsule under the pointer.
    private func watchShift() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isShiftDown = event.modifierFlags.contains(.shift)
            return event
        }
    }
}
