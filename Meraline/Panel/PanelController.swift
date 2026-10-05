import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

final class FloatingPanel: EditingPanel {
    var onEscape: (() -> Void)?
    var onClose: (() -> Void)?
    /// A pinch on the trackpad, anywhere over the window.
    var onMagnify: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The field being edited takes no drops, so what is dropped on the input falls through to the card, as
    /// anywhere else on it: text lands in a card of its own, as a selection does, and files and pictures attach.
    /// Otherwise the input would take them as typed, and dropped text with line breaks would show only its last
    /// line. SwiftUI's field editor signs up for drops each time a field starts editing, and again a moment
    /// after the first time, so this runs after each focus and when the window gives up the keyboard, which it
    /// does before anything can be dragged in from another app.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let made = super.makeFirstResponder(responder)
        leaveDropsToTheCard()
        return made
    }

    override func resignKey() {
        super.resignKey()
        leaveDropsToTheCard()
    }

    private func leaveDropsToTheCard() {
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor else { return }
        editor.unregisterDraggedTypes()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func performClose(_ sender: Any?) {
        onClose?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .magnify, let onMagnify {
            onMagnify(event)
        } else {
            super.sendEvent(event)
        }
    }
}

/// What the panel keeps between showings, in memory only: how tall the conversation may be, requests to
/// focus the input, which group under the input is open, the panel of actions open over the window, the
/// answers' zoom, and the last time the recent chats were forgotten.
@Observable
final class PanelLayout {
    /// The recent chats were forgotten, by a shake of the window or Clear Recent Chats, and how many went.
    /// `number` tells one time from the next.
    struct Forgetting: Equatable {
        let number: Int
        let count: Int
    }

    /// Whether the window is up, or on its way up: the card rises into place as it turns true and sinks as it turns
    /// false (`PanelRoot`), while `PanelController` fades the window.
    var isShown = false
    var maximumConversationHeight: CGFloat = 480
    /// Requests to give the keyboard to the input.
    var focusRequest = 0
    /// Requests to give the keyboard to the card for context written by hand (`TypedStateCard`), once it is open:
    /// from Tab, Decision's Write It, Add Text in the sparkle's panel, and a preset put in the input.
    var stateFocusRequest = 0
    /// The group under the input that is open, if any. It stays as it is while the window is hidden,
    /// until Meraline quits.
    var expandedTray: ModeBar.Tray?
    /// The panel of actions open over the window, if any (see `PanelContext`).
    var actionPanel: ActionPanelRequest?
    /// Counts the copies the actions made, for the footer to say Copied.
    var copyNotice = 0
    /// The answers that show what they changed in the text their question was about, in their place, by turn
    /// (see `TextChanges`).
    var answersShowingChanges: Set<ChatSession.Turn.ID> = []
    /// An answer of a bulk decision whose words or lines show under its header, by turn and answer (see
    /// `BulkDecisionCard`); every answer starts folded.
    struct OpenDecisionGroup: Hashable {
        let turn: ChatSession.Turn.ID
        let group: DecisionBatch.Group.ID
    }
    var openDecisionGroups: Set<OpenDecisionGroup> = []
    /// The last time the recent chats were forgotten, for the clock under the input to react to.
    var lastForgetting: Forgetting?
    /// Counts the drafts stashed in Recent Chats, for the clock under the input to say Stashed.
    var stashNotice = 0
    /// How far the window's top may rise before it leaves the screen, for a panel of actions to choose
    /// between opening upward and downward.
    var roomOnScreenAbove: CGFloat = .greatestFiniteMagnitude
    /// How large the answers are drawn, in every chat, until Meraline quits or ⌘0.
    var answerZoom = AnswerZoom.actualSize
    /// A choice ⌘1 to ⌘9 made on an agent's question that waits (see `PanelContext.promptChoices`): the ask and
    /// the choice's place, which the card answers as it would a click (`PromptCard`). `number` tells one press
    /// from the next.
    struct PromptChoice: Equatable {
        let prompt: AgentPrompt.ID
        let index: Int
        let number: Int
    }
    var promptChoice: PromptChoice?

    func choose(_ index: Int, of prompt: AgentPrompt.ID) {
        promptChoice = PromptChoice(prompt: prompt, index: index, number: (promptChoice?.number ?? 0) + 1)
    }

    /// Closes the panel of actions and gives the keyboard back to the input.
    func closeActionPanel() {
        actionPanel = nil
        focusRequest += 1
    }

    /// Esc in a panel of actions: a confirmation goes back to the list, unless the panel opened only for it,
    /// and a list closes.
    func cancelActionPanel() {
        guard let request = actionPanel else { return }
        if request.confirming != nil && !request.isConfirmationOnly {
            actionPanel?.confirming = nil
        } else {
            closeActionPanel()
        }
    }

    /// Opens a panel of actions, or closes it when it is the one open.
    func toggleActionPanel(_ kind: ActionPanelKind) {
        if actionPanel?.kind == kind {
            closeActionPanel()
        } else {
            actionPanel = ActionPanelRequest(kind: kind)
        }
    }

    /// ⌘+, ⌘−, or ⌘0 for the answers.
    func zoomAnswers(_ step: AnswerZoom.Step) {
        answerZoom = answerZoom.applying(step)
        Log.panel.info("Answers zoomed to \(self.answerZoom.percent)")
    }

    /// Show What Changed under an answer, or Show Answer once the changes show.
    func toggleChanges(of turn: ChatSession.Turn.ID) {
        if answersShowingChanges.remove(turn) == nil { answersShowingChanges.insert(turn) }
    }

    /// The answers of a bulk decision whose words or lines show.
    func openDecisionGroups(of turn: ChatSession.Turn.ID) -> Set<DecisionBatch.Group.ID> {
        Set(openDecisionGroups.lazy.filter { $0.turn == turn }.map(\.group))
    }

    /// A click on an answer's header in a bulk decision: opens its words or lines, or folds them back.
    func toggleDecisionGroup(_ group: DecisionBatch.Group.ID, of turn: ChatSession.Turn.ID) {
        let key = OpenDecisionGroup(turn: turn, group: group)
        if openDecisionGroups.remove(key) == nil { openDecisionGroups.insert(key) }
    }

    func noteForgotten(_ count: Int) {
        lastForgetting = Forgetting(number: (lastForgetting?.number ?? 0) + 1, count: count)
    }
}

final class PanelController: NSObject {
    static let width: CGFloat = 640
    /// The window's margin around the card, at its sides and top, where the card's shadow fades out.
    static let margin: CGFloat = 32
    /// The window's margin under the card, more than at its sides: the card's shadow is offset downward, and at the
    /// sides' margin it still showed, cut off in a hard line at the window's edge.
    static let marginBelow: CGFloat = 48
    private static var windowWidth: CGFloat { width + margin * 2 }

    private let panel: FloatingPanel
    private let session: ChatSession
    private let preferences: Preferences
    private let whatsNew: WhatsNew
    private let updater: Updater
    private let updateNotice: UpdateNotice
    private let shortcutSetup: ShortcutSetup
    let layout = PanelLayout()
    private let openSettings: (SettingsPane?) -> Void
    private var keyMonitor: Any?
    private var isApplyingFrame = false
    private var shake = ShakeDetector()
    /// How much of the window's height is room above the card, made for a panel of actions.
    private var roomAbove: CGFloat = 0
    /// The window's shrink to its content, waiting for the card to finish animating smaller.
    private var pendingShrink: Task<Void, Never>?
    /// The SwiftUI content, taller than the window and pinned to its top (see `sizeContent()`).
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var isReadingSelection = false
    /// Where what the buttons above the card added came from, which a paste counts toward too.
    private let sources = ContextSources()
    /// Insert Answer, which closes the window to paste into the app in front.
    private let inserter = AnswerInserter()
    private var activationObserver: NSObjectProtocol?

    init(session: ChatSession, preferences: Preferences, whatsNew: WhatsNew, updater: Updater, updateNotice: UpdateNotice, shortcutSetup: ShortcutSetup, openSettings: @escaping (SettingsPane?) -> Void) {
        self.session = session
        self.preferences = preferences
        self.whatsNew = whatsNew
        self.updater = updater
        self.updateNotice = updateNotice
        self.shortcutSetup = shortcutSetup
        self.openSettings = openSettings
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 136),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        // The content fades itself in and out (`PanelRoot`, as `show()` and `close()` ask); the system's
        // utility-window behavior showed the window in a cut.
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.handleEscape() }
        panel.onClose = { [weak self] in self?.close() }
        panel.onMagnify = { [weak self] in self?.magnify($0) }
        observeScreenSharingPreference()
        inserter.closeWindow = { [weak self] in self?.close(animated: false) }
        AnswerNotes.shared.configure(preferences: preferences) { [weak self] in self?.cardFrame }

        let view = ChatPanelView(
            session: session,
            preferences: preferences,
            whatsNew: whatsNew,
            updater: updater,
            updateNotice: updateNotice,
            shortcutSetup: shortcutSetup,
            layout: layout,
            onHeightChange: { [weak self] in self?.fit(height: $0, roomAbove: $1) },
            onClose: { [weak self] in self?.close() },
            openSettings: openSettings,
            takeKeyboard: { [weak self] in self?.show() },
            screen: { [weak self] in self?.panel.screen },
            refitInput: { [weak self] in self?.panel.refitFieldBeingEdited() },
            sources: sources,
            inserter: inserter
        )
        let root = PanelRoot(setup: shortcutSetup, layout: layout, chat: view, onHeightChange: { [weak self] in self?.fit(height: $0) }) { [weak self] in
            self?.layout.focusRequest += 1
        }
        hostingView.rootView = AnyView(root)
        hostingView.sizingOptions = []
        hostingView.focusRingType = .none
        // The content is laid out at a fixed height, pinned to the window's top, and the window shows as much of
        // it as the card needs. Resizing the window then never resizes what SwiftUI lays out: if it did, a card
        // growing with an animation would be drawn around its final middle, half its growth too low at first.
        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        hostingView.autoresizingMask = [.width, .minYMargin]
        container.addSubview(hostingView)
        panel.contentView = container
        sizeContent()

        // Another app in front means another screen to take a picture of.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.sources.screenChanged()
            }
        }
    }

    /// Whether the window is up. One fading out counts as closed, so ⌥ Space during its fade brings it back.
    var isVisible: Bool { panel.isVisible && !isClosing }
    /// Whether the window is fading out, before it is ordered out.
    private var isClosing = false
    /// Counts the closes begun, so a close undone by `show()` doesn't order the window out when its time comes.
    private var closes = 0
    /// How long the content takes to fade in, as the card rises into place, and to fade out, as it sinks back
    /// (`PanelRoot`, in SwiftUI, which Core Animation draws smoothly however busy the main thread is; a fade of the
    /// window's own alpha ran on a main-thread timer and showed in two or three steps). The window is ordered out by
    /// the clock, not the fade's end.
    static let fadeIn: TimeInterval = 0.18
    static let fadeOut: TimeInterval = 0.15

    /// The card on the screen while the window is up, for a torn-off answer to open beside.
    private var cardFrame: NSRect? {
        guard panel.isVisible else { return nil }
        let frame = panel.frame
        let top = frame.maxY - roomAbove - Self.margin - ContextButtons.roomAbove
        let bottom = frame.minY + Self.marginBelow
        return NSRect(x: frame.minX + Self.margin, y: bottom, width: Self.width, height: max(0, top - bottom))
    }

    func toggle() {
        isVisible ? close() : show()
    }

    /// The shortcut: closes the window, or opens it with what is selected in the app in front: text, on offer
    /// for the selection button above the card, or files and folders in Finder, attached. The selection is read
    /// first, while that app still has the keyboard, which is also why the button can't read it itself.
    func toggleBringingSelection() {
        guard !isReadingSelection else { return }
        // While the shortcut picker is up, a shortcut it is trying may be this one too.
        guard !shortcutSetup.isPresented else { return show() }
        guard !isVisible, preferences.bringsSelection else { return toggle() }
        // The fast Accessibility read runs while the app in front still has the keyboard, then the window shows at
        // once. Only the Copy-command fallback (browsers, editors) is slow; for apps that copy through their menu it
        // runs after the window is up, so the window no longer waits on it. An opaque app (Zed) gets ⌘C, which needs
        // that app still focused, so it reads before the window takes the keyboard. Only what is selected now comes:
        // with nothing selected, an earlier selection leaves the draft.
        switch SelectionReader.begin() {
        case .found(let found):
            session.bringCurrentSelection(text: found.text, files: found.files)
            show()
        case .nothing:
            session.bringCurrentSelection(text: nil, files: [])
            show()
        case .copy(let copy) where copy.opaque:
            isReadingSelection = true
            Task {
                let found = await SelectionReader.finish(copy)
                session.bringCurrentSelection(text: found?.text, files: found?.files ?? [])
                isReadingSelection = false
                show()
            }
        case .copy(let copy):
            show()
            isReadingSelection = true
            Task {
                let found = await SelectionReader.finish(copy)
                session.bringCurrentSelection(text: found?.text, files: found?.files ?? [])
                isReadingSelection = false
            }
        }
    }

    /// `meraline://play` without a game: the window, with the games open under the input.
    func showGames() {
        show()
        withAnimation(GameTray.spring) { layout.expandedTray = .games }
    }

    /// `meraline://ask?clipboard=1&screen=1`: adds what is on the clipboard and a screenshot of the screen the
    /// window is on, as the buttons above the card do, except that what is in the draft already stays in.
    /// Whether everything asked for is in the draft now. A game takes none of it.
    func addContext(clipboard: Bool, screen: Bool) async -> Bool {
        guard clipboard || screen else { return true }
        guard !session.isPlaying else { return false }
        var complete = true
        if clipboard, !sources.addClipboard(to: session) { complete = false }
        if screen, await !sources.addScreenshot(of: panel.screen, to: session) { complete = false }
        return complete
    }

    private var didWarmUp = false

    /// Builds the window's content and draws it once, off every screen, so the first ⌥ Space doesn't pay to lay
    /// out the whole panel and first-draw its glass. Deferred to just after launch; a no-op once it has run or
    /// once the window has been shown for real.
    func warmUp() {
        guard !didWarmUp, !panel.isVisible else { return }
        didWarmUp = true
        let clock = ContinuousClock()
        let start = clock.now
        sizeContent()
        hostingView.layoutSubtreeIfNeeded()
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: -50_000, y: -50_000))
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.setFrameOrigin(origin)
        Log.panel.info("Panel warmed up in \(Int((clock.now - start) / .milliseconds(1))) ms")
    }

    func show() {
        if isClosing {
            // Brought back during its fade out: the fade turns around, and the window is as it was.
            isClosing = false
            closes += 1
            layout.isShown = true
            panel.makeKeyAndOrderFront(nil)
            requestFocus()
            installKeyMonitor()
            sources.windowOpened()
            return
        }
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            layout.focusRequest += 1
            return
        }
        // A chat whose time ran out while the Mac slept goes before the window shows it.
        session.expireChats()
        session.prewarm()
        SelectionAccess.shared.refresh()
        let screen = Self.screenUnderPointer
        layout.maximumConversationHeight = max(220, screen.visibleFrame.height * 0.6)
        sizeContent()
        place(on: screen)
        // The content fades in as the card rises into place; with Reduce Motion it only fades.
        panel.makeKeyAndOrderFront(nil)
        layout.isShown = true
        requestFocus()
        installKeyMonitor()
        sources.windowOpened()
    }

    /// Gives the keyboard to the input a moment after the window shows: a focus set in the update that starts the
    /// content's fade, from nothing, never took, as one set in the update that inserts the Context card doesn't
    /// (`PanelLayout.stateFocusRequest`).
    private func requestFocus() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.layout.focusRequest += 1
        }
    }

    /// Gives the keyboard back to the input, with the cursor after its text: a field that takes the keyboard
    /// selects all of it, and the next key typed would replace it.
    private func focusInput() {
        layout.focusRequest += 1
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self else { return }
            PromptPresets.moveCursorToEnd(in: self.panel)
        }
    }

    /// Closes the window: it fades out as the card sinks, then is ordered out. Insert Answer closes it without the
    /// fade, since its paste needs the keyboard back in the app in front at once.
    func close(animated: Bool = true) {
        guard panel.isVisible, !isClosing else { return }
        shortcutSetup.dismiss()
        whatsNew.isExpanded = false
        session.withdrawOfferedSelection()
        sources.windowClosed()
        layout.actionPanel = nil
        removeKeyMonitor()
        layout.isShown = false
        guard animated else {
            panel.orderOut(nil)
            return
        }
        isClosing = true
        closes += 1
        let close = closes
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOut + 0.03))
            guard let self, self.closes == close else { return }
            self.isClosing = false
            self.panel.orderOut(nil)
        }
    }

    /// The Mac slept or locked, and Settings › General › Privacy says to forget (see `AwayWatcher`): every chat goes,
    /// with the answers torn off it, any panel of actions open over one, and the agents that remember it. The window
    /// stays as it was, empty. Says how many chats went.
    func forgetChats() -> Int {
        layout.actionPanel = nil
        AnswerNotes.shared.closeAll()
        let forgot = session.forgetAll()
        LiveAgents.shared.endAll()
        return forgot
    }

    /// Hide from Screen Sharing, in Settings › General and the sparkle's panel. macOS leaves the window out of the
    /// captures that respect it; those that take the whole display, as ScreenCaptureKit's do, may show it anyway.
    private func observeScreenSharingPreference() {
        withObservationTracking {
            panel.sharingType = preferences.hidesFromScreenSharing ? .none : .readOnly
        } onChange: {
            Task { @MainActor [weak self] in self?.observeScreenSharingPreference() }
        }
    }

    /// A pinch zooms the answers smoothly, wherever the pointer is over the window, and settles when it ends.
    private func magnify(_ event: NSEvent) {
        guard context.canZoomAnswers else { return }
        let ending = !event.phase.isDisjoint(with: [.ended, .cancelled])
        layout.answerZoom = layout.answerZoom.pinched(by: event.magnification, ending: ending)
        if ending { Log.panel.info("Answers pinched to \(self.layout.answerZoom.percent)") }
    }

    private func handleEscape() {
        if shortcutSetup.isPresented {
            shortcutSetup.dismiss()
        } else if layout.actionPanel != nil {
            layout.cancelActionPanel()
        } else if whatsNew.isExpanded {
            whatsNew.isExpanded = false
        } else if session.isStreaming {
            session.stop()
        } else if !session.turns.isEmpty || !session.draft.isEmpty || !session.draftImages.isEmpty || !session.draftFiles.isEmpty || !session.draftSelections.isEmpty || session.failure != nil || session.isPlaying {
            // While Live decisions are on, the draft goes to Recent Chats rather than away.
            if session.reset() { layout.stashNotice += 1 }
        } else {
            close()
        }
    }

    private func place(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let height = panel.frame.height
        var origin: NSPoint

        switch preferences.placement {
        case .screenCenter:
            origin = NSPoint(x: visible.midX - Self.windowWidth / 2, y: visible.maxY - visible.height * 0.2 - height)
        case .pointer:
            let pointer = NSEvent.mouseLocation
            origin = NSPoint(x: pointer.x - Self.windowWidth / 2, y: pointer.y - 16 - height + Self.margin)
        case .lastPosition:
            if let saved = UserDefaults.meraline.array(forKey: "panelTopLeft") as? [Double], saved.count == 2 {
                origin = NSPoint(x: saved[0], y: saved[1] - height)
            } else {
                origin = NSPoint(x: visible.midX - Self.windowWidth / 2, y: visible.maxY - visible.height * 0.2 - height)
            }
        }

        let frame = NSRect(origin: origin, size: NSSize(width: Self.windowWidth, height: height))
        apply(frame.clamped(to: Self.screen(containing: frame)?.visibleFrame ?? visible))
    }

    /// Fits the window to its content. The card's top stays where it is: the window grows and shrinks at the
    /// bottom, and room above the card, for a panel of actions that opens upward, raises the top instead. The
    /// window grows at once, so a growing card has room to animate into, and shrinks only once the card has
    /// animated smaller, so what leaves fades out instead of being cut off by the window's edge.
    private func fit(height: CGFloat, roomAbove above: CGFloat = 0) {
        let height = ceil(height)
        let above = ceil(above)
        pendingShrink?.cancel()
        pendingShrink = nil
        guard abs(panel.frame.height - height) > 0.5 || above != roomAbove else { return }
        if above == roomAbove, height < panel.frame.height, panel.isVisible {
            pendingShrink = Task { [weak self] in
                try? await Task.sleep(for: .seconds(ChatPanelView.cardAnimation + 0.1))
                guard !Task.isCancelled else { return }
                self?.resize(height: height, roomAbove: above)
            }
            return
        }
        resize(height: height, roomAbove: above)
    }

    /// Makes the content as tall as the tallest screen, so the window never outgrows it, pinned to the window's
    /// top. Called while the window is hidden, since a new height lays the content out again.
    private func sizeContent() {
        let height = max(1200, NSScreen.screens.map(\.frame.height).max() ?? 0)
        guard let container = panel.contentView, abs(hostingView.frame.height - height) > 0.5 else { return }
        hostingView.frame = NSRect(x: 0, y: container.bounds.height - height, width: container.bounds.width, height: height)
    }

    private func resize(height: CGFloat, roomAbove above: CGFloat) {
        var frame = panel.frame
        let top = frame.maxY - roomAbove + above
        roomAbove = above
        frame.origin.y = top - height
        frame.size.height = height
        apply(frame.clamped(to: (panel.screen ?? Self.screenUnderPointer).visibleFrame))
    }

    private func apply(_ frame: NSRect) {
        isApplyingFrame = true
        panel.setFrame(frame, display: true)
        isApplyingFrame = false
        measureRoomOnScreenAbove()
    }

    /// The room between the card's top, without any room made above it, and the top of the screen.
    private func measureRoomOnScreenAbove() {
        let visible = (panel.screen ?? Self.screenUnderPointer).visibleFrame
        let room = max(0, visible.maxY - (panel.frame.maxY - roomAbove))
        if abs(room - layout.roomOnScreenAbove) > 0.5 { layout.roomOnScreenAbove = room }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌘Return sends while the write-a-note card is open, as Return does in the input, ahead of Insert
            // Answer and the like, since the note's editor takes plain Return for a new line.
            if modifiers == .command, self.session.typedState != nil, self.layout.actionPanel == nil,
               !self.session.isStreaming,
               event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                self.session.send()
                return nil
            }
            if !self.shortcutSetup.isPresented, self.runAction(for: event) {
                return nil
            }
            // ⇧⌘N, as in the sparkle's panel.
            if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "n" {
                self.session.isAnonymous.toggle()
                return nil
            }
            // With a panel of actions open, the rest of the keys are for its search field.
            if self.layout.actionPanel != nil {
                return event
            }
            // Tab opens the card for writing a note to send with the question (`ChatSession.writeState`), in any
            // mode, and gives it the keyboard; from the card it goes back to the input, and takes the card away
            // when nothing was written in it (`leaveTypedState`), so Tab closes what Tab opened. Decision also
            // offers the card on its own row. It no longer sends — Return already does — and does nothing while
            // an answer streams or a game is on.
            if event.keyCode == UInt16(kVK_Tab), modifiers.isEmpty {
                if !self.session.isStreaming {
                    if let editor = self.panel.firstResponder as? NSTextView, !editor.isFieldEditor {
                        self.session.leaveTypedState()
                        self.focusInput()
                    } else {
                        self.session.writeState()
                        if self.session.typedState != nil { self.layout.stateFocusRequest += 1 }
                    }
                }
                return nil
            }
            // ⌫ in an empty input takes out the selection or the last attachment, like a token in Spotlight.
            // Not a repeat, so holding ⌫ to clear a question stops when the question is gone.
            if event.keyCode == UInt16(kVK_Delete), modifiers.isEmpty, !event.isARepeat, self.session.draft.isEmpty,
               !self.session.isStreaming, self.session.removeLastContext() {
                return nil
            }
            if modifiers == .command, event.charactersIgnoringModifiers == "v",
               self.pasteAttachments(from: .general) || (self.panel.firstResponder as? NSTextView)?.pasteOnOneLine(from: .general) == true {
                return nil
            }
            return event
        }
    }

    private var context: PanelContext {
        PanelContext(session: session, preferences: preferences, layout: layout, openSettings: openSettings, insertion: inserter.insertion)
    }

    /// ⌘K opens or closes the panel of actions: the chat's while a chat is open, the sparkle's otherwise. The
    /// shortcut of one of the chat's actions runs it, from anywhere in the window and with a panel open or
    /// not; one that can't be undone opens its confirmation. So do the mode toggle's ⌘1, ⌘2, and ⌘3, chat or no
    /// chat.
    private func runAction(for event: NSEvent) -> Bool {
        let modifiers = ActionShortcut.Modifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let context = context
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
            if layout.actionPanel != nil {
                layout.closeActionPanel()
            } else {
                layout.actionPanel = ActionPanelRequest(kind: context.chatMenu == nil ? .providers : .chat)
            }
            return true
        }
        guard let action = context.action(forKeyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: modifiers) else {
            return false
        }
        Log.panel.info("Shortcut runs \(action.id)")
        context.run(action, in: .chat, fromShortcut: true)
        return true
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Files copied in Finder, images or not, and image data from other apps. Anything else is text. What a
    /// paste attaches counts as the clipboard's, so the clipboard button takes it out rather than doubling it.
    private func pasteAttachments(from pasteboard: NSPasteboard) -> Bool {
        sources.refreshClipboard()
        let before = session.draftContextIDs
        defer { sources.note(session.draftContextIDs.subtracting(before), from: sources.clipboard, in: session) }
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !fileURLs.isEmpty {
            fileURLs.forEach(session.attach(fileAt:))
            return true
        }
        guard pasteboard.availableType(from: [.string]) == nil,
              let image = NSImage(pasteboard: pasteboard) else { return false }
        session.attach(image)
        return true
    }

    private static var screenUnderPointer: NSScreen {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
    }
}

extension PanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        layout.actionPanel = nil
        if !preferences.isPinned { close() }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard panel.isVisible else { return }
        sources.screenChanged()
    }

    /// Every step of a drag lands here. Besides remembering where the window is, each step goes to the
    /// shake detector: a shake while dragging forgets the recent chats.
    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, panel.isVisible else { return }
        UserDefaults.meraline.set([panel.frame.minX, panel.frame.maxY - roomAbove], forKey: "panelTopLeft")
        measureRoomOnScreenAbove()
        if shake.move(to: panel.frame.origin, at: ProcessInfo.processInfo.systemUptime) {
            forgetRecentChats()
        }
    }

    /// A shake of the window forgets the recent chats, and the clock under the input says so, offering Undo for
    /// a few seconds (see `ChatSession.shakeAwayHistory()`).
    private func forgetRecentChats() {
        let forgot = session.shakeAwayHistory()
        Log.panel.info("Window shaken: \(forgot) recent chat(s) forgotten")
        layout.noteForgotten(forgot)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }

    func clamped(to bounds: NSRect) -> NSRect {
        var frame = self
        frame.size.height = min(frame.height, bounds.height)
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        return frame
    }
}
