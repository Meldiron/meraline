import AppKit
import SwiftUI

/// What to ask next, under the last answer: two or three glass capsules, one under another, each a question
/// suggested on this Mac (see `FollowUps`). A click puts the question in the input without sending it, so it can be
/// changed first; a Shift-click asks it at once, and while Shift is down the capsule under the pointer shows an
/// arrow and turns the pink of the panel's other chosen states, as the presets above the card do. While they are
/// still being worked out (no `questions` yet), one capsule says so, and it becomes the first question when they
/// come, the others fading in under it. They show only while the input is empty and nothing streams. They fade
/// in, but go at once rather than fading out, so a new set never lies over the old one while it fades (two buttons
/// on one spot hung the hidden window, see `Announcements`). Each capsule is a glass container of its own, so its
/// fade reaches its glass.
struct FollowUpChips: View {
    let questions: [String]
    let choose: (_ question: String, _ sends: Bool) -> Void

    @State private var hovered: String?
    @State private var isShiftDown = false
    @State private var flagsMonitor: Any?

    static let transition: AnyTransition = .asymmetric(insertion: .opacity, removal: .identity)
    static let loadingText = "Thinking of follow-ups…"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // By place, so the capsule that said they were coming is the one that becomes the first question.
            ForEach(Array(shown.enumerated()), id: \.offset) { _, question in
                chip(question)
                    .transition(Self.transition)
            }
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

    /// The questions, or nil for the one capsule that says they are coming.
    private var shown: [String?] {
        questions.isEmpty ? [nil] : questions
    }

    private func chip(_ question: String?) -> some View {
        let sends = question != nil && isShiftDown && hovered == question
        return GlassEffectContainer {
            Button { if let question { click(question) } } label: {
                ChipLabel(question: question, sends: sends)
                    .glassEffect(sends ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(question != nil)
        }
        .animation(.smooth(duration: 0.2), value: sends)
        .onHover { isOver in
            guard let question else { return }
            if isOver {
                hovered = question
                isShiftDown = NSEvent.modifierFlags.contains(.shift)
            } else if hovered == question {
                hovered = nil
            }
        }
        .hoverTip(question == nil ? "" : "Put it in the input, or Shift-click to ask it now")
        .accessibilityLabel(question ?? "Thinking of follow-ups")
        .accessibilityHint(question == nil ? "" : "Puts the question in the input. Shift-click asks it.")
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

/// A follow-up's arrow and question, or the dots and words that say they are coming. While a Shift-click would send
/// it, the arrow points up in pink over a semibold question, like the mode toggle's chosen segment.
private struct ChipLabel: View {
    let question: String?
    let sends: Bool

    private var symbol: String {
        guard question != nil else { return "ellipsis" }
        return sends ? "arrow.up" : "arrow.turn.down.right"
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sends ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating, isActive: question == nil)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 14)
            Text(question ?? FollowUpChips.loadingText)
                .font(.system(size: 12, weight: sends ? .semibold : .medium))
                .foregroundStyle(question == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }
}
