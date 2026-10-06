import AppKit
import Observation
import SwiftUI

/// Answers torn off the window into small floating glass notes (Tear Off Answer, ⌘T), so a recipe or a list of
/// steps stays on the screen while you follow it in another app. A note moves by its header or any empty space,
/// resizes from its sides and bottom, can fold its question away, and zooms its answer on its own (⌘+, ⌘−, ⌘0,
/// or a pinch), starting from the window's zoom. Answers torn off while it is open stack in it (`NoteStack`): the
/// newest in front, the edges of the next two peeking out under it, and a count badge in its header that brings
/// the next one forward, so you flip through them without opening the window. It keeps its answers in memory
/// only: its cross, Esc while it has the keyboard, or ⌘W puts away the one in front, ⌥ and its cross the whole
/// pile, as quitting does, and nothing of it is saved. The note floats above other apps on every Space, beside the
/// window when there is room, and hides from screen sharing when the window does.
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

    /// A note's card width while it fits its answer: wider as its answer is zoomed, so larger words don't wrap
    /// into a narrow column.
    static func width(for zoom: AnswerZoom) -> CGFloat {
        min(max(width * zoom.scale, minimumWidth), maximumWidth)
    }

    /// The note, with every answer torn off into it, while it is open.
    private var note: AnswerNoteWindow?
    /// The card of the window the answers come from, in screen coordinates, to open a note beside it.
    private var anchor: () -> NSRect? = { nil }
    private var preferences: Preferences?
    /// Whether a new note shows its question: as the last note was left, until Meraline quits.
    fileprivate var showsQuestion = true

    /// The answers in the note, none while it is closed.
    var stack: NoteStack { note?.stack ?? NoteStack() }

    /// Called once by the window, which the notes open beside and take their sharing setting from.
    func configure(preferences: Preferences, anchor: @escaping () -> NSRect?) {
        self.preferences = preferences
        self.anchor = anchor
        observeScreenSharingPreference()
    }

    /// Opens an answer in the note, headed by the question it answers, with an agent's paths in it leading into
    /// `workspace` as they do in the window: on top of the pile when the note is open, at the zoom the note has, or
    /// in a new note beside the window at the window's zoom. `level` and `origin` are for pictures of a note taken
    /// where nobody sees it; a note floats beside the window otherwise.
    func open(answer: String, question: String, zoom: AnswerZoom = .actualSize, workspace: URL? = nil, level: NSWindow.Level = .floating, at origin: NSPoint? = nil) {
        if let note {
            note.add(answer: answer, question: question, workspace: workspace)
            Log.panel.info("Answer torn off onto the note's pile, \(note.stack.count) in it")
            return
        }
        let note = AnswerNoteWindow(
            answer: answer,
            question: question,
            zoom: zoom,
            workspace: workspace,
            showsQuestion: showsQuestion,
            hidesFromScreenSharing: preferences?.hidesFromScreenSharing ?? false,
            level: level
        ) { [weak self] window in
            if self?.note === window { self?.note = nil }
            Log.panel.info("Answer note closed")
        }
        note.show(at: origin ?? self.origin(for: note.size))
        self.note = note
        Log.panel.info("Answer torn off into a note")
    }

    func closeAll() {
        note?.close()
    }

    /// Beside the window's card, on the right when the screen has room there and on the left otherwise, its top
    /// level with the card's; without a window, the top right of the screen under the pointer.
    private func origin(for size: NSSize) -> NSPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = (anchor().flatMap { card in NSScreen.screens.first { $0.frame.intersects(card) } } ?? screen).visibleFrame
        var origin: NSPoint
        if let card = anchor() {
            let top = card.maxY + Self.margin
            let right = card.maxX + 12 - Self.margin
            let left = card.minX - 12 - size.width + Self.margin
            let x = right + size.width <= visible.maxX ? right : left
            origin = NSPoint(x: x, y: top - size.height)
        } else {
            origin = NSPoint(x: visible.maxX - size.width - 16 + Self.margin, y: visible.maxY - size.height + Self.margin - 16)
        }
        origin.x = min(max(origin.x, visible.minX - Self.margin), visible.maxX - size.width + Self.margin)
        origin.y = min(max(origin.y, visible.minY - Self.margin), visible.maxY - size.height + Self.margin)
        return origin
    }

    private func observeScreenSharingPreference() {
        guard let preferences else { return }
        withObservationTracking {
            let hides = preferences.hidesFromScreenSharing
            note?.hidesFromScreenSharing = hides
        } onChange: {
            Task { @MainActor [weak self] in self?.observeScreenSharingPreference() }
        }
    }
}

/// What a note shows and how it is sized: fitted to its answer until you resize it, then as you left it.
@Observable
private final class NoteLayout {
    /// The pile as it shows, which follows the window's once the answer in front has faded out.
    var stack = NoteStack()
    /// The answer's fade while another note comes forward.
    var contentOpacity = 1.0
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

/// The note's window: borderless and clear, with the card drawing its own rounded shadow, like the main window.
/// It floats, takes the keyboard only when clicked, and puts away the answer in front on Esc, ⌘W, or its cross, and
/// itself with the last. Its SwiftUI content fills it, so a resize lays the answer out again at the new size. A
/// pinch over it zooms its answers, as do ⌘+, ⌘−, and ⌘0 while it has the keyboard.
private final class AnswerNoteWindow: NSObject, NSWindowDelegate {
    private let panel: NotePanel
    private let layout: NoteLayout
    private let onClose: (AnswerNoteWindow) -> Void
    private var isClosed = false
    /// Where the window and the pointer were when a resize began.
    private var resizeStart: (frame: NSRect, pointer: NSPoint)?
    /// The window's shrink to a smaller card, waiting for the card's own animation to end.
    private var pendingShrink: Task<Void, Never>?
    /// The answers in the note, changed at once, while what shows follows after a fade.
    private(set) var stack = NoteStack()

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
        stack.add(answer: answer, question: question, workspace: workspace)
        layout.stack = stack
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
        panel.onClose = { [weak self] in self?.closeFront() }
        panel.onStep = { [weak self] step in self?.take(step) ?? false }
        panel.onZoom = { [weak self] step in self?.zoom(step) ?? false }
        panel.onMagnify = { [weak self] event in
            guard let self else { return }
            let ending = !event.phase.isDisjoint(with: [.ended, .cancelled])
            self.setZoom(self.layout.zoom.pinched(by: event.magnification, ending: ending))
        }
        self.hidesFromScreenSharing = hidesFromScreenSharing

        let hostingView = NSHostingView(rootView: AnswerNoteView(
            layout: layout,
            actions: NoteActions(
                close: { [weak self] in self?.closeFront() },
                closeAll: { [weak self] in self?.close() },
                step: { [weak self] step in _ = self?.take(step) },
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

    /// Puts the answer on top of the pile, in front, and the note in front of other windows.
    func add(answer: String, question: String, workspace: URL?) {
        flip { $0.add(answer: answer, question: question, workspace: workspace) }
        panel.orderFrontRegardless()
    }

    /// Puts the whole note away, every answer in it.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        pendingShrink?.cancel()
        panel.orderOut(nil)
        onClose(self)
    }

    /// Puts away the answer in front, and the note with its last.
    private func closeFront() {
        guard stack.count > 1 else { return close() }
        flip { $0.removeFront() }
    }

    /// Brings the next note forward, or the one before. False when there is no other.
    private func take(_ step: NoteStack.Step) -> Bool {
        guard stack.count > 1 else { return false }
        flip { $0.take(step) }
        return true
    }

    /// Changes the note in front: its answer fades out, then the card takes the next one's size as it fades in.
    /// The pile changes at once, so presses in quick succession count in order, and what shows catches up with it
    /// by the clock rather than the fade's end, which a hidden window may never reach.
    private func flip(_ change: (inout NoteStack) -> Void) {
        change(&stack)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layout.stack = stack
            return
        }
        withAnimation(.easeIn(duration: 0.08)) { layout.contentOpacity = 0 }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !self.isClosed else { return }
            withAnimation(.smooth(duration: 0.25)) {
                self.layout.stack = self.stack
                self.layout.contentOpacity = 1
            }
        }
    }

    /// Fits the window to the card while the note is sized by its answer, keeping its top where it is. It grows
    /// at once and shrinks once the card has, so a card shrinking with an animation is never cut off.
    private func fit(height: CGFloat) {
        guard layout.fitsAnswer else { return }
        let height = ceil(max(height, AnswerNotes.minimumHeight + AnswerNotes.margin * 2))
        pendingShrink?.cancel()
        guard abs(panel.frame.height - height) > 0.5 else { return }
        if height < panel.frame.height, panel.isVisible {
            pendingShrink = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.setHeight(height)
            }
            return
        }
        setHeight(height)
    }

    private func setHeight(_ height: CGFloat) {
        guard layout.fitsAnswer else { return }
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
            pendingShrink?.cancel()
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

    /// Zooms the answers. While the note fits its answer, it widens and narrows with the zoom, its left edge where
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
    /// ⌃⇥, ⇧⌘], and the ones back, which say whether there was another note to bring forward.
    var onStep: ((NoteStack.Step) -> Bool)?
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
            return
        }
        if event.type == .keyDown, let onStep,
           let step = NoteStack.Step(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags),
           onStep(step) {
            return
        }
        super.sendEvent(event)
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
    /// Puts away the answer in front.
    let close: () -> Void
    let closeAll: () -> Void
    let step: (NoteStack.Step) -> Void
    /// The note's height with its margins, while it is sized by its answer.
    let fit: (CGFloat) -> Void
    let resize: (NoteEdges) -> Void
    let endResize: () -> Void
    let toggleQuestion: () -> Void
    let zoom: (AnswerZoom.Step) -> Void
}

/// A torn-off answer in a card of neutral glass: a header with the question it answers, which folds away, and
/// buttons to copy the answer or put the note away, over the answer, which scrolls when it runs long. The answers
/// behind it peek out under the card, and the badge in the header brings the next forward.
private struct AnswerNoteView: View {
    let layout: NoteLayout
    let actions: NoteActions

    @State private var answerHeight: CGFloat = 0
    @State private var showsCopied = false
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private static let cornerRadius = NoteStackGeometry.cornerRadius
    /// How thick the strips along the sides and bottom that resize the note are.
    private static let edge: CGFloat = 8

    private var answer: String { layout.stack.front?.answer ?? "" }
    private var question: String { layout.stack.front?.question ?? "" }
    /// How many answers peek out under the one in front.
    private var depth: CGFloat { CGFloat(layout.stack.peeking.count) }

    private var maximumHeight: CGFloat {
        max(200, (NSScreen.main?.visibleFrame.height ?? 800) * 0.6)
    }

    var body: some View {
        GlassEffectContainer {
            card
                .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        }
        .padding(.bottom, NoteStackGeometry.room(for: depth))
        .background { PeekingEdges(depth: depth) }
        .background { shadow }
        .overlay(alignment: .leading) { resizeStrip(.leading).frame(width: Self.edge).padding(.vertical, 18).offset(x: -Self.edge * 0.75) }
        .overlay(alignment: .trailing) { resizeStrip(.trailing).frame(width: Self.edge).padding(.vertical, 18).offset(x: Self.edge * 0.75) }
        .overlay(alignment: .bottom) { resizeStrip(.bottom).frame(height: Self.edge).padding(.horizontal, 18).offset(y: Self.edge * 0.75) }
        .overlay(alignment: .bottomLeading) { resizeStrip([.leading, .bottom]).frame(width: 18, height: 18).offset(x: -Self.edge * 0.75, y: Self.edge * 0.75) }
        .overlay(alignment: .bottomTrailing) { resizeStrip([.trailing, .bottom]).frame(width: 18, height: 18).offset(x: Self.edge * 0.75, y: Self.edge * 0.75) }
        .padding(AnswerNotes.margin)
        .fixedSize(horizontal: false, vertical: layout.fitsAnswer)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { actions.fit($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.2), value: layout.showsQuestion)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Answer note")
    }

    /// The card's shadow, drawn on its own behind the glass: a shadow on glass shows only while the note has the
    /// keyboard, and one on the card itself would fall from every word and button on it. The pile's own shape is
    /// cut out, so none of it shows through the glass.
    private var shadow: some View {
        let shape = NoteStackOutline(depth: depth)
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
                    .environment(\.answerWorkspace, layout.stack.front?.workspace)
                    .opacity(layout.contentOpacity)
                    .background(OverlayScrollers())
            }
            .scrollPosition($scrollPosition)
            .frame(height: layout.fitsAnswer ? min(answerHeight, maximumHeight) : nil)
            .frame(maxHeight: layout.fitsAnswer ? nil : .infinity)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            // Another note in front starts at its top, while its answer is faded out.
            .onChange(of: layout.stack.front?.id) { scrollPosition.scrollTo(edge: .top) }
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
                    .opacity(layout.contentOpacity)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
            if !layout.zoom.isActualSize {
                AnswerZoomBadge(zoom: layout.zoom, height: 26) { actions.zoom(.actualSize) }
                    .transition(.opacity)
            }
            if layout.stack.badge != nil {
                NoteStackBadge(stack: layout.stack, step: actions.step)
                    .transition(.opacity)
            }
            noteButton(layout.showsQuestion ? "chevron.up" : "chevron.down", label: layout.showsQuestion ? "Hide Question" : "Show Question", action: actions.toggleQuestion)
            noteButton(showsCopied ? "checkmark" : "doc.on.doc", label: showsCopied ? "Copied" : "Copy Answer", action: copy)
            noteButton("xmark", label: "Close Note", help: layout.stack.count > 1 ? "Close Note (⌥ for All Notes)" : nil) {
                NSEvent.modifierFlags.contains(.option) ? actions.closeAll() : actions.close()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: layout.showsQuestion ? 40 : 36)
        .animation(.smooth(duration: 0.2), value: layout.zoom.isActualSize)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    private func noteButton(_ symbol: String, label: String, help: String? = nil, action: @escaping () -> Void) -> some View {
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
        .help(help ?? label)
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
        AnswerExport.copy(answer, to: .general)
        withAnimation(.smooth(duration: 0.2)) { showsCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.smooth(duration: 0.2)) { showsCopied = false }
        }
    }
}
