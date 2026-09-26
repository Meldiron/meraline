import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func performClose(_ sender: Any?) {
        onClose?()
    }
}

/// What the panel keeps between showings, in memory only: how tall the conversation may be, requests to
/// focus the input, which group under the input is open, the panel of actions open over the window, and the
/// last time the recent chats were forgotten.
@Observable
final class PanelLayout {
    /// The recent chats were forgotten, by a shake of the window or Clear Recent Chats, and how many went.
    /// `number` tells one time from the next.
    struct Forgetting: Equatable {
        let number: Int
        let count: Int
    }

    var maximumConversationHeight: CGFloat = 480
    var focusRequest = 0
    /// The group under the input that is open, if any. It stays as it is while the window is hidden,
    /// until Meraline quits.
    var expandedTray: ModeBar.Tray?
    /// The panel of actions open over the window, if any (see `PanelContext`).
    var actionPanel: ActionPanelRequest?
    /// Counts the copies the actions made, for the footer to say Copied.
    var copyNotice = 0
    /// The last time the recent chats were forgotten, for the clock under the input to react to.
    var lastForgetting: Forgetting?
    /// How far the window's top may rise before it leaves the screen, for a panel of actions to choose
    /// between opening upward and downward.
    var roomOnScreenAbove: CGFloat = .greatestFiniteMagnitude

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

    func noteForgotten(_ count: Int) {
        lastForgetting = Forgetting(number: (lastForgetting?.number ?? 0) + 1, count: count)
    }
}

final class PanelController: NSObject {
    static let width: CGFloat = 640
    static let margin: CGFloat = 32
    private static var windowWidth: CGFloat { width + margin * 2 }

    private let panel: FloatingPanel
    private let session: ChatSession
    private let preferences: Preferences
    private let whatsNew: WhatsNew
    private let shortcutSetup: ShortcutSetup
    private let layout = PanelLayout()
    private let openSettings: (SettingsPane?) -> Void
    private var keyMonitor: Any?
    private var isApplyingFrame = false
    private var hiddenAt: Date?
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
    private var activationObserver: NSObjectProtocol?

    init(session: ChatSession, preferences: Preferences, whatsNew: WhatsNew, shortcutSetup: ShortcutSetup, openSettings: @escaping (SettingsPane?) -> Void) {
        self.session = session
        self.preferences = preferences
        self.whatsNew = whatsNew
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
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.handleEscape() }
        panel.onClose = { [weak self] in self?.close() }

        let view = ChatPanelView(
            session: session,
            preferences: preferences,
            whatsNew: whatsNew,
            shortcutSetup: shortcutSetup,
            layout: layout,
            onHeightChange: { [weak self] in self?.fit(height: $0, roomAbove: $1) },
            onClose: { [weak self] in self?.close() },
            openSettings: openSettings,
            takeKeyboard: { [weak self] in self?.show() },
            screen: { [weak self] in self?.panel.screen },
            sources: sources
        )
        let root = PanelRoot(setup: shortcutSetup, chat: view, onHeightChange: { [weak self] in self?.fit(height: $0) }) { [weak self] in
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

    var isVisible: Bool { panel.isVisible }

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
        isReadingSelection = true
        Task {
            // Only what is selected now: with nothing selected, an earlier selection leaves the draft.
            let found = await SelectionReader.read()
            session.bringCurrentSelection(text: found?.text, files: found?.files ?? [])
            isReadingSelection = false
            show()
        }
    }

    func show() {
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            layout.focusRequest += 1
            return
        }
        if preferences.idleReset.hasExpired(since: hiddenAt) { session.expire() }
        hiddenAt = nil
        if preferences.activeProvider?.isOnDevice == true { AppleIntelligenceClient.prewarm() }
        SelectionAccess.shared.refresh()
        let screen = Self.screenUnderPointer
        layout.maximumConversationHeight = max(220, screen.visibleFrame.height * 0.6)
        sizeContent()
        place(on: screen)
        panel.makeKeyAndOrderFront(nil)
        layout.focusRequest += 1
        installKeyMonitor()
        sources.windowOpened()
    }

    func close() {
        guard panel.isVisible else { return }
        shortcutSetup.dismiss()
        hiddenAt = .now
        whatsNew.isExpanded = false
        session.withdrawOfferedSelection()
        sources.windowClosed()
        layout.actionPanel = nil
        panel.orderOut(nil)
        removeKeyMonitor()
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
            session.reset()
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
            if let saved = UserDefaults.standard.array(forKey: "panelTopLeft") as? [Double], saved.count == 2 {
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
            if event.keyCode == UInt16(kVK_Tab), modifiers.isEmpty {
                self.session.send()
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
        PanelContext(session: session, preferences: preferences, layout: layout, openSettings: openSettings)
    }

    /// ⌘K opens or closes the panel of actions: the chat's while a chat is open, the sparkle's otherwise. The
    /// shortcut of one of the chat's actions runs it, from anywhere in the window and with a panel open or
    /// not; one that can't be undone opens its confirmation.
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
        UserDefaults.standard.set([panel.frame.minX, panel.frame.maxY - roomAbove], forKey: "panelTopLeft")
        measureRoomOnScreenAbove()
        if shake.move(to: panel.frame.origin, at: ProcessInfo.processInfo.systemUptime) {
            forgetRecentChats()
        }
    }

    /// A shake of the window forgets the recent chats, and the clock under the input says so.
    private func forgetRecentChats() {
        let forgot = session.forgetHistory()
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
