import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

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

@Observable
final class PanelLayout {
    var maximumConversationHeight: CGFloat = 480
    var focusRequest = 0
}

final class PanelController: NSObject {
    static let width: CGFloat = 640

    private let panel: FloatingPanel
    private let session: ChatSession
    private let preferences: Preferences
    private let layout = PanelLayout()
    private var pasteMonitor: Any?
    private var isApplyingFrame = false

    init(session: ChatSession, preferences: Preferences, openSettings: @escaping () -> Void) {
        self.session = session
        self.preferences = preferences
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 72),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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
            layout: layout,
            onHeightChange: { [weak self] in self?.fit(height: $0) },
            onClose: { [weak self] in self?.close() },
            openSettings: openSettings
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            layout.focusRequest += 1
            return
        }
        let screen = Self.screenUnderPointer
        layout.maximumConversationHeight = max(220, screen.visibleFrame.height * 0.6)
        place(on: screen)
        panel.makeKeyAndOrderFront(nil)
        layout.focusRequest += 1
        installPasteMonitor()
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        removePasteMonitor()
        session.reset()
    }

    private func handleEscape() {
        if session.isStreaming {
            session.stop()
        } else if !session.draft.isEmpty || !session.draftImages.isEmpty {
            session.clearDraft()
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
            origin = NSPoint(x: visible.midX - Self.width / 2, y: visible.maxY - visible.height * 0.2 - height)
        case .pointer:
            let pointer = NSEvent.mouseLocation
            origin = NSPoint(x: pointer.x - Self.width / 2, y: pointer.y - 16 - height)
        case .lastPosition:
            if let saved = UserDefaults.standard.array(forKey: "panelTopLeft") as? [Double], saved.count == 2 {
                origin = NSPoint(x: saved[0], y: saved[1] - height)
            } else {
                origin = NSPoint(x: visible.midX - Self.width / 2, y: visible.maxY - visible.height * 0.2 - height)
            }
        }

        let frame = NSRect(origin: origin, size: NSSize(width: Self.width, height: height))
        apply(frame.clamped(to: Self.screen(containing: frame)?.visibleFrame ?? visible))
    }

    private func fit(height: CGFloat) {
        let height = ceil(height)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        apply(frame.clamped(to: (panel.screen ?? Self.screenUnderPointer).visibleFrame))
    }

    private func apply(_ frame: NSRect) {
        isApplyingFrame = true
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        isApplyingFrame = false
    }

    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.panel,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  self.pasteImages(from: .general) else { return event }
            return nil
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
    }

    private func pasteImages(from pasteboard: NSPasteboard) -> Bool {
        let imageURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]
        ) as? [URL] ?? []
        if !imageURLs.isEmpty {
            imageURLs.forEach(session.attach(fileAt:))
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
        if preferences.closesOnDeactivation { close() }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, panel.isVisible else { return }
        UserDefaults.standard.set([panel.frame.minX, panel.frame.maxY], forKey: "panelTopLeft")
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
