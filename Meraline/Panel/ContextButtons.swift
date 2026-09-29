import AppKit
import KeyboardShortcuts
import SwiftUI

/// Glass circles above the card, at its left, that add context to the next question, as much of it as you
/// like: the text selected when the shortcut opened the window (⇧⌘E), what is on the clipboard (⇧⌘V), and a
/// screenshot of the screen the window is on, taken without Meraline's own windows (⇧⌘S). Each click adds
/// what the button has now, so texts from several apps or screenshots of several visits all come along;
/// only when that very text, copy, or visit is in the draft already does a click take it out again (see
/// `ContextSources`). Each circle shows which it would do: faded to a ghost of itself when there is nothing
/// to add, neutral glass when it would add, and the active pin's pink while what it has is in the draft. A capsule beside them says
/// when a button couldn't do its part. `ContextSources` does the adding, so `meraline://ask?clipboard=1&screen=1`
/// adds exactly as a click does. Games take none of it, so the buttons step aside while one is on.
struct ContextButtons: View {
    /// The circles' size, like the pin's and the gear's.
    static let size: CGFloat = 32
    /// From the window's top to the circles, and from the circles to the card.
    static let inset: CGFloat = 10
    /// How much the row adds above the card, beyond the window's usual margin.
    static let roomAbove: CGFloat = inset + size + inset - PanelController.margin

    /// What a button would do if clicked.
    enum Status: Equatable {
        /// Nothing to add: no text was selected, the clipboard holds nothing Meraline can add, or the draft
        /// has all the images it can take.
        case unavailable
        /// A click adds.
        case available
        /// What the button has now is in the draft; a click takes it out.
        case added
    }

    let session: ChatSession
    let preferences: Preferences
    let sources: ContextSources
    /// The screen the window is on, for the screenshot.
    let screen: () -> NSScreen?
    /// Closes the window, so the system's request for access isn't hidden behind it.
    let close: () -> Void
    /// Gives the keyboard back to the input.
    let focusInput: () -> Void

    @State private var selectionsAdded = 0

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                selectionButton
                clipboardButton
                screenshotButton
                if let note = sources.notice {
                    noteCapsule(note)
                }
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .opacity(session.isPlaying ? 0 : 1)
        .disabled(session.isPlaying)
        .animation(.smooth(duration: 0.2), value: sources.notice)
        .animation(.smooth(duration: 0.2), value: session.isPlaying)
        .animation(.smooth(duration: 0.2), value: statuses)
        .task(id: sources.noticesShown) {
            guard sources.notice?.fades == true else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, sources.notice?.fades == true else { return }
            sources.notice = nil
        }
    }

    private var statuses: [Status] {
        [selectionStatus, clipboardStatus, screenshotStatus]
    }

    private func noteCapsule(_ note: Note) -> some View {
        let allow: (() -> Void)? = note == .noScreenAccess ? { allowScreenRecording() } : nil
        return NoteCapsule(note: note, allow: allow) { sources.notice = nil }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
    }

    private var selectionButton: some View {
        let status = selectionStatus
        return ContextButton(status: status, label: "Selected Text", help: selectionHelp(status), key: "e", action: toggleSelection) {
            SelectionIcon(status: status)
                .keyframeAnimator(initialValue: 1.0, trigger: selectionsAdded) { icon, scale in
                    icon.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.22, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.36, spring: .bouncy)
                }
        }
    }

    private var clipboardButton: some View {
        let status = clipboardStatus
        return ContextButton(status: status, label: "Clipboard", help: clipboardHelp(status), key: "v", action: toggleClipboard) {
            Image(systemName: "clipboard")
                .symbolEffect(.bounce, value: sources.clipboardsAdded)
        }
    }

    private var screenshotButton: some View {
        let status = screenshotStatus
        return ContextButton(status: status, label: "Screenshot", help: screenshotHelp(status), key: "s", action: toggleScreenshot) {
            Image(systemName: "display")
                .symbolEffect(.bounce, value: sources.screenshotsAdded)
                .symbolEffect(.pulse, options: .repeating, isActive: sources.isCapturing)
        }
    }

    // MARK: What each button would do

    private var selectionStatus: Status {
        guard session.offeredSelection != nil else { return .unavailable }
        return session.isOfferedSelectionAdded ? .added : .available
    }

    private var clipboardStatus: Status {
        if !sources.items(from: sources.clipboard, in: session).isEmpty { return .added }
        // A decision reads text only.
        return (session.isDeciding ? sources.clipboardHasText : sources.clipboardHasContent) ? .available : .unavailable
    }

    private var screenshotStatus: Status {
        if !sources.items(from: sources.screen, in: session).isEmpty { return .added }
        guard !session.isDeciding else { return .unavailable }
        return session.draftImages.count < ImageAttachment.limit ? .available : .unavailable
    }

    private func selectionHelp(_ status: Status) -> String {
        switch status {
        case .added:
            return "Take the selected text out (⇧⌘E)"
        case .available:
            guard let offered = session.offeredSelection else { return "" }
            let words = offered.wordCount
            let source = offered.appName.map { " in \($0)" } ?? ""
            return "Add the text selected\(source), \(words.formatted()) \(words == 1 ? "word" : "words") (⇧⌘E)"
        case .unavailable:
            if !preferences.bringsSelection { return "Turn on Bring the selection in Settings › General to add selected text" }
            if !SelectionAccess.shared.isGranted { return "Meraline needs Accessibility access to read the selection" }
            return "Select text in an app, then press \(Self.shortcut) to add it here"
        }
    }

    private func clipboardHelp(_ status: Status) -> String {
        switch status {
        case .added: "Take out what you added from the clipboard (⇧⌘V)"
        case .available: "Add what’s on the clipboard (⇧⌘V)"
        case .unavailable: session.isDeciding ? "Nothing on the clipboard a decision can read; it takes text only" : "Nothing on the clipboard Meraline can add"
        }
    }

    private func screenshotHelp(_ status: Status) -> String {
        switch status {
        case .added: "Take out the screenshot of this screen (⇧⌘S)"
        case .available: "Add a screenshot of this screen, without Meraline (⇧⌘S)"
        case .unavailable: session.isDeciding ? "A decision reads text only, so no screenshot goes with it" : "A question can take up to \(ImageAttachment.limit) images"
        }
    }

    /// The window's shortcut as macOS shows it, such as ⌥ Space.
    private static var shortcut: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "the shortcut"
    }

    // MARK: Clicks

    /// A button did its part: a note that was only passing on news goes, and the input takes the keyboard.
    private func done() {
        if sources.notice?.fades == true { sources.notice = nil }
        focusInput()
    }

    private func toggleSelection() {
        let wasAdded = session.isOfferedSelectionAdded
        guard session.toggleOfferedSelection() else { return }
        Log.panel.info("Selection button \(wasAdded ? "took out" : "added") the offered text")
        if !wasAdded { selectionsAdded += 1 }
        done()
    }

    private func toggleClipboard() {
        sources.refreshClipboard()
        let added = sources.items(from: sources.clipboard, in: session)
        if !added.isEmpty {
            session.removeContext(added)
            Log.panel.info("Clipboard button took out \(added.count) item(s)")
            return done()
        }
        if sources.addClipboard(to: session) { done() }
    }

    private func toggleScreenshot() {
        guard !sources.isCapturing else { return }
        let added = sources.items(from: sources.screen, in: session)
        if !added.isEmpty {
            session.removeContext(added)
            Log.panel.info("Screenshot button took out the screenshot")
            return done()
        }
        Task {
            if await sources.addScreenshot(of: screen(), to: session) { done() }
        }
    }

    private func allowScreenRecording() {
        close()
        ScreenCapture.requestAccess()
    }
}

extension ContextButtons {
    enum Note: Equatable {
        case emptyClipboard
        case screenshotFailed
        /// Stays until access is allowed or the cross puts it away.
        case noScreenAccess

        var fades: Bool { self != .noScreenAccess }

        var text: String {
            switch self {
            case .emptyClipboard: "Nothing on the clipboard to add"
            case .screenshotFailed: "Couldn’t take a screenshot"
            case .noScreenAccess: "Screenshots need Screen Recording access"
            }
        }

        var symbol: String {
            switch self {
            case .emptyClipboard: "clipboard"
            case .screenshotFailed: "exclamationmark.triangle"
            case .noScreenAccess: "lock"
            }
        }
    }
}

/// One of the circles, with ⇧⌘ and its key, dressed for its status: faded to `unavailableOpacity` and still
/// when there is nothing to add, so it reads as out of use next to one that would add, neutral glass when a
/// click adds, and the active pin's pink, symbol and a faint glass tint, while what it has is in the draft.
private struct ContextButton<Icon: View>: View {
    let status: ContextButtons.Status
    let label: String
    let help: String
    let key: KeyEquivalent
    let action: () -> Void
    @ViewBuilder let icon: Icon

    /// How much of a circle with nothing to add shows. The row's shadow comes from what it draws, so the
    /// circle's shadow fades with it and it lies flat and gray beside the ones that would add.
    static var unavailableOpacity: Double { 0.4 }

    var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: ContextButtons.size, height: ContextButtons.size)
                .glassEffect(glass, in: .circle)
                .contentShape(.circle)
                .opacity(status == .unavailable ? Self.unavailableOpacity : 1)
        }
        .buttonStyle(.plain)
        .disabled(status == .unavailable)
        .keyboardShortcut(key, modifiers: [.command, .shift])
        .hoverTip(help, edge: .bottom)
        .accessibilityLabel(label)
        .accessibilityValue(status == .added ? "Added" : status == .unavailable ? "Nothing to add" : "")
        .accessibilityAddTraits(status == .added ? .isSelected : [])
    }

    private var foreground: AnyShapeStyle {
        switch status {
        case .unavailable: AnyShapeStyle(.tertiary)
        case .available: AnyShapeStyle(.secondary)
        case .added: AnyShapeStyle(Color.meralinePink)
        }
    }

    private var glass: Glass {
        switch status {
        case .unavailable: .regular
        case .available: .regular.interactive()
        case .added: .regular.tint(.meralinePink.opacity(0.22)).interactive()
        }
    }
}

/// Selected text: a highlight with a text cursor standing at its end, in the button's own color, with the
/// highlight a paler wash of it.
private struct SelectionIcon: View {
    let status: ContextButtons.Status

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.4)
                .fill(highlight)
                .frame(width: 11, height: 8)
                .offset(x: -2)
            IBeam()
                .frame(width: 6, height: 15)
                .offset(x: 3.5)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private var highlight: AnyShapeStyle {
        switch status {
        case .unavailable: AnyShapeStyle(.tertiary.opacity(0.4))
        case .available: AnyShapeStyle(.secondary.opacity(0.45))
        case .added: AnyShapeStyle(Color.meralinePink.opacity(0.3))
        }
    }
}

/// A text cursor: a stem with a short bar across each end.
private struct IBeam: Shape {
    func path(in rect: CGRect) -> Path {
        let stroke = rect.width * 0.27
        let bar = CGSize(width: rect.width, height: stroke)
        let corner = CGSize(width: stroke / 2, height: stroke / 2)
        var path = Path()
        path.addRect(CGRect(x: rect.midX - stroke / 2, y: rect.minY + stroke / 2, width: stroke, height: rect.height - stroke))
        path.addRoundedRect(in: CGRect(origin: CGPoint(x: rect.minX, y: rect.minY), size: bar), cornerSize: corner)
        path.addRoundedRect(in: CGRect(origin: CGPoint(x: rect.minX, y: rect.maxY - stroke), size: bar), cornerSize: corner)
        return path
    }
}

/// What a button has to say, in a glass capsule beside it. When the screenshot needs access, it offers the
/// way to allow it, with the faint pink of the panel's buttons, and a cross.
private struct NoteCapsule: View {
    let note: ContextButtons.Note
    let allow: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(note.text, systemImage: note.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let allow {
                Button("Allow…", action: allow)
                    .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                    .controlSize(.small)
                    .hoverTip("Ask macOS for Screen Recording access. Meraline takes one picture when you ask and records nothing.", edge: .bottom)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, allow == nil ? 12 : 6)
        .frame(height: ContextButtons.size)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
