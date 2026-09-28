import AppKit
import Observation
import SwiftUI

/// Answers torn off the window into small floating glass notes (Tear Off Answer, ⌘T), so a recipe or a list of
/// steps stays on the screen while you follow it in another app. A note moves by its header or any empty space,
/// resizes from its sides and bottom, can fold its question away, and zooms its answer on its own (⌘+, ⌘−, ⌘0,
/// or a pinch), starting from the window's zoom. It keeps its answer in memory only: its
/// cross, Esc while it has the keyboard, or quitting puts it away, and nothing of it is saved. Notes float above
/// other apps on every Space, beside the window when there is room, and hide from screen sharing when the window
/// does.
final class AnswerNotes {
    static let shared = AnswerNotes()

    /// A new note's card width, and how narrow and wide one may be made.
    static let width: CGFloat = 320
    static let minimumWidth: CGFloat = 240
    static let maximumWidth: CGFloat = 900
    /// How short a note may be made.
    static let minimumHeight: CGFloat = 90
    /// The room around the card for its shadow, as the window has.
    static let margin: CGFloat = 28
    /// How far each note opens from the one before, down and to the right.
    private static let cascade: CGFloat = 26

    /// A note's card width while it fits its answer: wider as its answer is zoomed, so larger words don't wrap
    /// into a narrow column.
    static func width(for zoom: AnswerZoom) -> CGFloat {
        min(max(width * zoom.scale, minimumWidth), maximumWidth)
    }

    private var notes: [AnswerNoteWindow] = []
    /// The card of the window the answers come from, in screen coordinates, to open a note beside it.
    private var anchor: () -> NSRect? = { nil }
    private var preferences: Preferences?
    /// Whether a new note shows its question: as the last note was left, until Meraline quits.
    fileprivate var showsQuestion = true

    /// How many notes are open.
    var count: Int { notes.count }

    /// Called once by the window, which the notes open beside and take their sharing setting from.
    func configure(preferences: Preferences, anchor: @escaping () -> NSRect?) {
        self.preferences = preferences
        self.anchor = anchor
        observeScreenSharingPreference()
    }

    /// Opens an answer in a note of its own, headed by the question it answers, at the window's zoom, with an
    /// agent's paths in it leading into `workspace` as they do in the window. `level` and `origin` are for pictures
    /// of a note taken where nobody sees it; a note floats beside the window otherwise.
    func open(answer: String, question: String, zoom: AnswerZoom = .actualSize, workspace: URL? = nil, level: NSWindow.Level = .floating, at origin: NSPoint? = nil) {
        let note = AnswerNoteWindow(
            answer: answer,
            question: question,
            zoom: zoom,
            workspace: workspace,
            showsQuestion: showsQuestion,
            hidesFromScreenSharing: preferences?.hidesFromScreenSharing ?? false,
            level: level
        ) { [weak self] window in
            self?.notes.removeAll { $0 === window }
            Log.panel.info("Answer note closed, \(self?.notes.count ?? 0) open")
        }
        note.show(at: origin ?? self.origin(for: note.size))
        notes.append(note)
        Log.panel.info("Answer torn off into a note, \(notes.count) open")
    }

    func closeAll() {
        for note in notes { note.close() }
    }

    /// Beside the window's card, on the right when the screen has room there and on the left otherwise, its top
    /// level with the card's; without a window, the top right of the screen under the pointer. Each note after
    /// the first opens a little lower and further right, so none hides another.
    private func origin(for size: NSSize) -> NSPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = (anchor().flatMap { card in NSScreen.screens.first { $0.frame.intersects(card) } } ?? screen).visibleFrame
        let offset = CGFloat(notes.count) * Self.cascade
        var origin: NSPoint
        if let card = anchor() {
            let top = card.maxY + Self.margin
            let right = card.maxX + 12 - Self.margin
            let left = card.minX - 12 - size.width + Self.margin
            let x = right + size.width <= visible.maxX ? right : left
            origin = NSPoint(x: x + offset, y: top - size.height - offset)
        } else {
            origin = NSPoint(x: visible.maxX - size.width - 16 + Self.margin - offset, y: visible.maxY - size.height + Self.margin - 16 - offset)
        }
        origin.x = min(max(origin.x, visible.minX - Self.margin), visible.maxX - size.width + Self.margin)
        origin.y = min(max(origin.y, visible.minY - Self.margin), visible.maxY - size.height + Self.margin)
        return origin
    }

    private func observeScreenSharingPreference() {
        guard let preferences else { return }
        withObservationTracking {
            let hides = preferences.hidesFromScreenSharing
            for note in notes { note.hidesFromScreenSharing = hides }
        } onChange: {
            Task { @MainActor [weak self] in self?.observeScreenSharingPreference() }
        }
    }
}

/// What a note shows and how it is sized: fitted to its answer until you resize it, then as you left it.
@Observable
private final class NoteLayout {
    var fitsAnswer = true
    var showsQuestion: Bool
    var zoom: AnswerZoom

    init(showsQuestion: Bool, zoom: AnswerZoom) {
        self.showsQuestion = showsQuestion
        self.zoom = zoom
    }
}

/// The sides of a note that a resize moves.
private struct NoteEdges: OptionSet {
    let rawValue: Int
    static let leading = NoteEdges(rawValue: 1 << 0)
    static let trailing = NoteEdges(rawValue: 1 << 1)
    static let bottom = NoteEdges(rawValue: 1 << 2)
}

/// One note's window: borderless and clear, with the card drawing its own rounded shadow, like the main window.
/// It floats, takes the keyboard only when clicked, and closes on Esc, ⌘W, or its cross. Its SwiftUI content fills
/// it, so a resize lays the answer out again at the new size. A pinch over it zooms its answer, as do ⌘+, ⌘−, and
/// ⌘0 while it has the keyboard.
private final class AnswerNoteWindow: NSObject, NSWindowDelegate {
    private let panel: NotePanel
    private let layout: NoteLayout
    private let onClose: (AnswerNoteWindow) -> Void
    private var isClosed = false
    /// Where the window and the pointer were when a resize began.
    private var resizeStart: (frame: NSRect, pointer: NSPoint)?

    var size: NSSize { panel.frame.size }

    var hidesFromScreenSharing: Bool {
        get { panel.sharingType == .none }
        set { panel.sharingType = newValue ? .none : .readOnly }
    }

    init(
        answer: String,
        question: String,
        zoom: AnswerZoom,
        workspace: URL?,
        showsQuestion: Bool,
        hidesFromScreenSharing: Bool,
        level: NSWindow.Level,
        onClose: @escaping (AnswerNoteWindow) -> Void
    ) {
        self.onClose = onClose
        layout = NoteLayout(showsQuestion: showsQuestion, zoom: zoom)
        panel = NotePanel(
            contentRect: NSRect(x: 0, y: 0, width: AnswerNotes.width(for: zoom) + AnswerNotes.margin * 2, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onClose = { [weak self] in self?.close() }
        panel.onZoom = { [weak self] step in self?.zoom(step) ?? false }
        panel.onMagnify = { [weak self] event in
            guard let self else { return }
            let ending = !event.phase.isDisjoint(with: [.ended, .cancelled])
            self.setZoom(self.layout.zoom.pinched(by: event.magnification, ending: ending))
        }
        self.hidesFromScreenSharing = hidesFromScreenSharing

        let hostingView = NSHostingView(rootView: AnswerNoteView(
            answer: answer,
            question: question,
            workspace: workspace,
            layout: layout,
            actions: NoteActions(
                close: { [weak self] in self?.close() },
                fit: { [weak self] height in self?.fit(height: height) },
                resize: { [weak self] edges in self?.resize(edges) },
                endResize: { [weak self] in self?.resizeStart = nil },
                toggleQuestion: { [weak self] in self?.toggleQuestion() },
                zoom: { [weak self] step in _ = self?.zoom(step) }
            )
        ))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        // Laying the note out now tells the window its height (`fit`) before it shows.
        hostingView.layoutSubtreeIfNeeded()
    }

    /// Shows the note once its answer has been laid out, so it doesn't open short and grow.
    func show(at origin: NSPoint) {
        panel.setFrameOrigin(origin)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard let self, !self.isClosed else { return }
            self.panel.orderFrontRegardless()
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        panel.orderOut(nil)
        onClose(self)
    }

    /// Fits the window to the card while the note is sized by its answer, keeping its top where it is.
    private func fit(height: CGFloat) {
        guard layout.fitsAnswer else { return }
        let height = ceil(max(height, AnswerNotes.minimumHeight + AnswerNotes.margin * 2))
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        // A long answer that grew past the screen's bottom moves up, its shadow's margin allowed off screen.
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.y = max(frame.origin.y, visible.minY - AnswerNotes.margin)
        }
        panel.setFrame(frame, display: true)
    }

    /// Follows the pointer from where the resize began, by screen coordinates, since the edge being dragged moves
    /// with the window. From then on the note keeps the size you give it.
    private func resize(_ edges: NoteEdges) {
        let pointer = NSEvent.mouseLocation
        if resizeStart == nil {
            resizeStart = (panel.frame, pointer)
            layout.fitsAnswer = false
        }
        guard let start = resizeStart else { return }
        let margins = AnswerNotes.margin * 2
        var frame = start.frame
        if !edges.isDisjoint(with: [.leading, .trailing]) {
            let dx = pointer.x - start.pointer.x
            let width = edges.contains(.trailing) ? start.frame.width + dx : start.frame.width - dx
            frame.size.width = min(max(width, AnswerNotes.minimumWidth + margins), AnswerNotes.maximumWidth + margins)
            if edges.contains(.leading) { frame.origin.x = start.frame.maxX - frame.width }
        }
        if edges.contains(.bottom) {
            let tallest = ((panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) + margins
            let height = start.frame.height - (pointer.y - start.pointer.y)
            frame.size.height = min(max(height, AnswerNotes.minimumHeight + margins), tallest)
            frame.origin.y = start.frame.maxY - frame.height
        }
        panel.setFrame(frame, display: true)
    }

    private func toggleQuestion() {
        layout.showsQuestion.toggle()
        AnswerNotes.shared.showsQuestion = layout.showsQuestion
    }

    /// ⌘+, ⌘−, or ⌘0. False when the zoom is as far as that step goes.
    private func zoom(_ step: AnswerZoom.Step) -> Bool {
        guard layout.zoom.allows(step) else { return false }
        setZoom(layout.zoom.applying(step))
        Log.panel.info("Answer note zoomed to \(self.layout.zoom.percent)")
        return true
    }

    /// Zooms the answer. While the note fits its answer, it widens and narrows with the zoom, its left edge where
    /// it was unless the screen's edge is in the way; once you have resized it, it keeps the size you gave it.
    private func setZoom(_ zoom: AnswerZoom) {
        guard zoom != layout.zoom else { return }
        layout.zoom = zoom
        guard layout.fitsAnswer else { return }
        let margin = AnswerNotes.margin
        var frame = panel.frame
        frame.size.width = AnswerNotes.width(for: zoom) + margin * 2
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.width, visible.width + margin * 2)
            frame.origin.x = min(max(frame.minX, visible.minX - margin), visible.maxX + margin - frame.width)
        }
        panel.setFrame(frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}

private final class NotePanel: EditingPanel {
    var onClose: (() -> Void)?
    /// ⌘+, ⌘−, or ⌘0, which says whether it zoomed.
    var onZoom: ((AnswerZoom.Step) -> Bool)?
    /// A pinch on the trackpad over the note.
    var onMagnify: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, let onZoom,
           let step = AnswerZoom.Step(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: ActionShortcut.Modifiers(event.modifierFlags)),
           onZoom(step) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .magnify, let onMagnify {
            onMagnify(event)
        } else {
            super.sendEvent(event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func performClose(_ sender: Any?) {
        onClose?()
    }
}

/// What the note's buttons and edges ask of its window.
private struct NoteActions {
    let close: () -> Void
    /// The note's height with its margins, while it is sized by its answer.
    let fit: (CGFloat) -> Void
    let resize: (NoteEdges) -> Void
    let endResize: () -> Void
    let toggleQuestion: () -> Void
    let zoom: (AnswerZoom.Step) -> Void
}

/// A torn-off answer in a card of neutral glass: a header with the question it answers, which folds away, and
/// buttons to copy the answer or put the note away, over the answer, which scrolls when it runs long.
private struct AnswerNoteView: View {
    let answer: String
    let question: String
    /// The chat's workspace, which an agent's relative paths in the answer start from; nil for an LLM's.
    let workspace: URL?
    let layout: NoteLayout
    let actions: NoteActions

    @State private var answerHeight: CGFloat = 0
    @State private var showsCopied = false

    private static let cornerRadius: CGFloat = 20
    /// How thick the strips along the sides and bottom that resize the note are.
    private static let edge: CGFloat = 8

    private var maximumHeight: CGFloat {
        max(200, (NSScreen.main?.visibleFrame.height ?? 800) * 0.6)
    }

    var body: some View {
        GlassEffectContainer {
            card
                .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
                .background { shadow }
                .overlay(alignment: .leading) { resizeStrip(.leading).frame(width: Self.edge).padding(.vertical, 18).offset(x: -Self.edge * 0.75) }
                .overlay(alignment: .trailing) { resizeStrip(.trailing).frame(width: Self.edge).padding(.vertical, 18).offset(x: Self.edge * 0.75) }
                .overlay(alignment: .bottom) { resizeStrip(.bottom).frame(height: Self.edge).padding(.horizontal, 18).offset(y: Self.edge * 0.75) }
                .overlay(alignment: .bottomLeading) { resizeStrip([.leading, .bottom]).frame(width: 18, height: 18).offset(x: -Self.edge * 0.75, y: Self.edge * 0.75) }
                .overlay(alignment: .bottomTrailing) { resizeStrip([.trailing, .bottom]).frame(width: 18, height: 18).offset(x: Self.edge * 0.75, y: Self.edge * 0.75) }
        }
        .padding(AnswerNotes.margin)
        .fixedSize(horizontal: false, vertical: layout.fitsAnswer)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { actions.fit($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.2), value: layout.showsQuestion)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Answer note")
    }

    /// The card's shadow, drawn on its own behind the glass: a shadow on glass shows only while the note has the
    /// keyboard, and one on the card itself would fall from every word and button on it. The card's own shape is
    /// cut out, so none of it shows through the glass.
    private var shadow: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return shape
            .fill(.black)
            .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
            .mask {
                Rectangle()
                    .padding(-AnswerNotes.margin)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            if layout.showsQuestion {
                Divider()
                    .padding(.horizontal, 14)
            }
            ScrollView {
                MarkdownView(markdown: answer, fontSize: 13.5)
                    .padding(.horizontal, 16)
                    .padding(.top, layout.showsQuestion ? 12 : 0)
                    .padding(.bottom, 14)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { answerHeight = $0 }
                    .environment(\.answerZoom, layout.zoom.scale)
                    .environment(\.answerWorkspace, workspace)
            }
            .frame(height: layout.fitsAnswer ? min(answerHeight, maximumHeight) : nil)
            .frame(maxHeight: layout.fitsAnswer ? nil : .infinity)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: layout.fitsAnswer ? nil : .infinity, alignment: .top)
        .background { WindowDragArea() }
    }

    /// The question, or nothing once folded away, and the note's buttons. Dragging it moves the note.
    private var header: some View {
        HStack(spacing: 6) {
            if layout.showsQuestion {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.meralinePink)
                Text(question.isEmpty ? "Answer" : question.onOneLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(question)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
            if !layout.zoom.isActualSize {
                AnswerZoomBadge(zoom: layout.zoom, height: 26) { actions.zoom(.actualSize) }
                    .transition(.opacity)
            }
            noteButton(layout.showsQuestion ? "chevron.up" : "chevron.down", label: layout.showsQuestion ? "Hide Question" : "Show Question", action: actions.toggleQuestion)
            noteButton(showsCopied ? "checkmark" : "doc.on.doc", label: showsCopied ? "Copied" : "Copy Answer", action: copy)
            noteButton("xmark", label: "Close Note", action: actions.close)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: layout.showsQuestion ? 40 : 36)
        .animation(.smooth(duration: 0.2), value: layout.zoom.isActualSize)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    private func noteButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// An invisible strip along an edge, with the resize pointer, that resizes the note as it is dragged.
    private func resizeStrip(_ edges: NoteEdges) -> some View {
        Color.clear
            .contentShape(.rect)
            .pointerStyle(.frameResize(position: Self.position(of: edges)))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { _ in actions.resize(edges) }
                    .onEnded { _ in actions.endResize() }
            )
            .allowsWindowActivationEvents(true)
            .accessibilityHidden(true)
    }

    private static func position(of edges: NoteEdges) -> FrameResizePosition {
        switch (edges.contains(.leading), edges.contains(.trailing), edges.contains(.bottom)) {
        case (true, _, true): .bottomLeading
        case (_, true, true): .bottomTrailing
        case (true, _, _): .leading
        case (_, true, _): .trailing
        default: .bottom
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        withAnimation(.smooth(duration: 0.2)) { showsCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.smooth(duration: 0.2)) { showsCopied = false }
        }
    }
}
