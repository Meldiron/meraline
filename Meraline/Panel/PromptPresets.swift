import AppKit
import SwiftUI

/// Glass capsules above the card, at its right, lined up with the gear: the presets of Settings › Prompt (see
/// `PromptPreset`), each its icon and its name. A click puts the preset's text in the input, ahead of whatever is
/// typed there, and a second click takes it out again; a Shift-click sends it at once, and while Shift is down the
/// capsule under the pointer shows an arrow for it. The preset whose text starts the input wears the active pin's
/// pink. When the names don't fit beside the buttons on the left, only the icons show, and past that the row
/// scrolls. Here presets are for a chat's first question: once the chat starts they sink into the card one after
/// another, to rise again for the next chat, and the chat's actions (⌘K) offer them for its answer instead. They stay in the view
/// tree all along, faded and disabled, so nothing is inserted or removed while the window is hidden (see
/// `Announcements`).
struct PromptPresets: View {
    let presets: [PromptPreset]
    let draft: String
    let isShown: Bool
    let apply: (PromptPreset, _ sends: Bool) -> Void

    /// How wide the row is with the names, and how much room it has.
    @State private var titledWidth: CGFloat = 0
    @State private var room: CGFloat = 0
    @State private var hovered: PromptPreset.ID?
    @State private var isShiftDown = false
    @State private var flagsMonitor: Any?

    /// Room around the row inside its scroll view, which would otherwise clip the capsules' shadow. Below, it
    /// reaches the card's top and no further.
    private static let shadowRoom = ContextButtons.inset
    /// How far a capsule sinks while it goes, from above the card to its edge.
    private static let sinking = ContextButtons.inset

    var body: some View {
        let applied = PromptPreset.applied(in: draft, among: presets)?.id
        let showsTitles = titledWidth <= room
        ScrollView(.horizontal) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                        // From the gear outward.
                        bubble(preset, isApplied: preset.id == applied, showsTitle: showsTitles, order: presets.count - 1 - index)
                    }
                }
            }
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
            .padding(Self.shadowRoom)
            .frame(minWidth: room + Self.shadowRoom * 2, alignment: .trailing)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: ContextButtons.size + Self.shadowRoom * 2)
        .padding(-Self.shadowRoom)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { room = $0 }
        .background {
            // The row with its names, never drawn, to tell whether they fit.
            HStack(spacing: 8) {
                ForEach(presets) { PresetLabel(preset: $0, symbol: $0.shownSymbol, showsTitle: true, isApplied: false) }
            }
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { titledWidth = $0 }
        }
        .animation(.smooth(duration: 0.2), value: applied)
        .animation(.smooth(duration: 0.25), value: showsTitles)
        .onAppear(perform: watchShift)
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
        }
    }

    private func bubble(_ preset: PromptPreset, isApplied: Bool, showsTitle: Bool, order: Int) -> some View {
        let sends = isShiftDown && hovered == preset.id
        return Button { click(preset) } label: {
            PresetLabel(preset: preset, symbol: sends ? "arrow.up" : preset.shownSymbol, showsTitle: showsTitle, isApplied: isApplied)
                .glassEffect(isApplied ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isOver in
            if isOver {
                hovered = preset.id
                isShiftDown = NSEvent.modifierFlags.contains(.shift)
            } else if hovered == preset.id {
                hovered = nil
            }
        }
        .help(help(for: preset, isApplied: isApplied))
        .accessibilityLabel(preset.title.isEmpty ? "Preset" : preset.title)
        .accessibilityHint("Puts the preset in the input. Shift-click sends it.")
        .accessibilityAddTraits(isApplied ? .isSelected : [])
        // Sinks into the card as the chat starts, the capsule by the gear first, and rises again for the next chat.
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown ? 1 : 0.7, anchor: .bottom)
        .offset(y: isShown ? 0 : Self.sinking)
        .animation(
            isShown
                ? .spring(duration: 0.45, bounce: 0.3).delay(0.08 + Double(order) * 0.04)
                : .smooth(duration: 0.22).delay(Double(order) * 0.03),
            value: isShown
        )
        .disabled(!isShown)
        .accessibilityHidden(!isShown)
    }

    private func help(for preset: PromptPreset, isApplied: Bool) -> String {
        let name = preset.title.isEmpty ? "the preset" : preset.title
        return isApplied ? "Take \(name) out of the input" : "Put \(name) in the input, or Shift-click to send it"
    }

    private func click(_ preset: PromptPreset) {
        let event = NSApp.currentEvent
        let sends = (event?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift)
        apply(preset, sends)
        guard !sends, let window = event?.window else { return }
        Task {
            // Once SwiftUI has put the text in the input and given it the keyboard.
            try? await Task.sleep(for: .milliseconds(50))
            Self.moveCursorToEnd(in: window)
        }
    }

    /// Puts the input's cursor after its text. A field that takes the keyboard selects all of its text, and the
    /// first key typed after the preset would replace it.
    static func moveCursorToEnd(in window: NSWindow) {
        guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return }
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.setSelectedRange(end)
        editor.scrollRangeToVisible(end)
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

/// A preset's icon and name, or its icon alone in a circle the size of the buttons on the left. The icon and name
/// are the active pin's pink and the primary color while the preset starts the input, like the mode toggle's
/// chosen segment.
private struct PresetLabel: View {
    let preset: PromptPreset
    let symbol: String
    let showsTitle: Bool
    let isApplied: Bool

    private var title: String? {
        showsTitle && !preset.title.trimmed.isEmpty ? preset.title.trimmed : nil
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isApplied ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: isApplied ? .semibold : .medium))
                    .foregroundStyle(isApplied ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .padding(.leading, title == nil ? 0 : 11)
        .padding(.trailing, title == nil ? 0 : 13)
        .frame(minWidth: ContextButtons.size, minHeight: ContextButtons.size)
    }
}
