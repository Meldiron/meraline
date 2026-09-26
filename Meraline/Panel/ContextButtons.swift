import AppKit
import KeyboardShortcuts
import SwiftUI

/// Glass circles above the card, at its left, that add context to the next question, as much of it as you
/// like: the text selected when the shortcut opened the window (⇧⌘E), what is on the clipboard (⇧⌘V), and a
/// screenshot of the screen the window is on, taken without Meraline's own windows (⇧⌘S). Each click adds
/// what the button has now, so texts from several apps or screenshots of several visits all come along;
/// only when that very text, copy, or visit is in the draft already does a click take it out again (see
/// `ContextSources`). Each circle shows which it would do: dimmed when there is nothing to add, neutral glass
/// when it would add, and the active pin's pink while what it has is in the draft. A capsule beside them says
/// when a button couldn't do its part. Games take none of it, so the buttons step aside while one is on.
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

    @State private var note: Note?
    /// Counts the notes shown, so a note shown again stays its full time.
    @State private var notesShown = 0
    @State private var isCapturing = false
    @State private var selectionsAdded = 0
    @State private var clipboardsAdded = 0
    @State private var screenshotsAdded = 0

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                selectionButton
                clipboardButton
                screenshotButton
                if let note {
                    noteCapsule(note)
                }
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .opacity(session.isPlaying ? 0 : 1)
        .disabled(session.isPlaying)
        .animation(.smooth(duration: 0.2), value: note)
        .animation(.smooth(duration: 0.2), value: session.isPlaying)
        .animation(.smooth(duration: 0.2), value: statuses)
        .task(id: notesShown) {
            guard note?.fades == true else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, note?.fades == true else { return }
            note = nil
        }
    }

    private var statuses: [Status] {
        [selectionStatus, clipboardStatus, screenshotStatus]
    }

    private func noteCapsule(_ note: Note) -> some View {
        let allow: (() -> Void)? = note == .noScreenAccess ? { allowScreenRecording() } : nil
        return NoteCapsule(note: note, allow: allow) { self.note = nil }
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
                .symbolEffect(.bounce, value: clipboardsAdded)
        }
    }

    private var screenshotButton: some View {
        let status = screenshotStatus
        return ContextButton(status: status, label: "Screenshot", help: screenshotHelp(status), key: "s", action: toggleScreenshot) {
            Image(systemName: "display")
                .symbolEffect(.bounce, value: screenshotsAdded)
                .symbolEffect(.pulse, options: .repeating, isActive: isCapturing)
        }
    }

    // MARK: What each button would do

    private var selectionStatus: Status {
        guard session.offeredSelection != nil else { return .unavailable }
        return session.isOfferedSelectionAdded ? .added : .available
    }

    private var clipboardStatus: Status {
        if !sources.items(from: sources.clipboard, in: session).isEmpty { return .added }
        return sources.clipboardHasContent ? .available : .unavailable
    }

    private var screenshotStatus: Status {
        if !sources.items(from: sources.screen, in: session).isEmpty { return .added }
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
        case .unavailable: "Nothing on the clipboard Meraline can add"
        }
    }

    private func screenshotHelp(_ status: Status) -> String {
        switch status {
        case .added: "Take out the screenshot of this screen (⇧⌘S)"
        case .available: "Add a screenshot of this screen, without Meraline (⇧⌘S)"
        case .unavailable: "A question can take up to \(ImageAttachment.limit) images"
        }
    }

    /// The window's shortcut as macOS shows it, such as ⌥ Space.
    private static var shortcut: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "the shortcut"
    }

    // MARK: Clicks

    private func show(_ note: Note) {
        self.note = note
        notesShown += 1
    }

    /// A button did its part: a note that was only passing on news goes, and the input takes the keyboard.
    private func done() {
        if note?.fades == true { note = nil }
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
        let origin = sources.clipboard
        let added = sources.items(from: origin, in: session)
        if !added.isEmpty {
            session.removeContext(added)
            Log.panel.info("Clipboard button took out \(added.count) item(s)")
            return done()
        }
        guard let content = ClipboardContent.read(from: .general) else {
            Log.panel.info("Clipboard button: nothing to add")
            return show(.emptyClipboard)
        }
        Log.panel.info("Clipboard button added \(content.logDescription)")
        sources.note(session.addClipboard(content), from: origin, in: session)
        clipboardsAdded += 1
        done()
    }

    private func toggleScreenshot() {
        guard !isCapturing else { return }
        let origin = sources.screen
        let added = sources.items(from: origin, in: session)
        if !added.isEmpty {
            session.removeContext(added)
            Log.panel.info("Screenshot button took out the screenshot")
            return done()
        }
        guard ScreenCapture.hasAccess else {
            Log.panel.info("Screenshot button: no Screen Recording access")
            return show(.noScreenAccess)
        }
        guard let screen = screen() else { return show(.screenshotFailed) }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let image = try await ScreenCapture.image(of: screen)
                let before = session.draftContextIDs
                session.attach(image)
                sources.note(session.draftContextIDs.subtracting(before), from: origin, in: session)
                Log.panel.info("Screenshot button added the screen")
                if note == .noScreenAccess { note = nil }
                screenshotsAdded += 1
                done()
            } catch ScreenCapture.Failure.noAccess {
                Log.panel.info("Screenshot button: Screen Recording access refused")
                show(.noScreenAccess)
            } catch {
                Log.panel.error("Screenshot failed: \(error.localizedDescription)")
                show(.screenshotFailed)
            }
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

/// One of the circles, with ⇧⌘ and its key, dressed for its status: dimmed and still when there is nothing
/// to add, neutral glass when a click adds, and the active pin's pink, symbol and a faint glass tint, while
/// what it has is in the draft.
private struct ContextButton<Icon: View>: View {
    let status: ContextButtons.Status
    let label: String
    let help: String
    let key: KeyEquivalent
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: ContextButtons.size, height: ContextButtons.size)
                .glassEffect(glass, in: .circle)
                .contentShape(.circle)
                .opacity(status == .unavailable ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(status == .unavailable)
        .keyboardShortcut(key, modifiers: [.command, .shift])
        .help(help)
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
                    .help("Ask macOS for Screen Recording access. Meraline takes one picture when you ask and records nothing.")
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
