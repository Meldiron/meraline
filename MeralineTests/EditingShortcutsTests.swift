import AppKit
import Carbon.HIToolbox
import Testing
@testable import Meraline

@MainActor
struct EditingShortcutsTests {
    /// A text view that counts the commands it gets, so the tests never touch the clipboard.
    final class RecordingTextView: NSTextView {
        var received: [Selector] = []
        override func copy(_ sender: Any?) { received.append(#selector(copy(_:))) }
        override func cut(_ sender: Any?) { received.append(#selector(cut(_:))) }
        override func paste(_ sender: Any?) { received.append(#selector(paste(_:))) }
        override func selectAll(_ sender: Any?) { received.append(#selector(selectAll(_:))) }
    }

    private func press(_ characters: String, _ modifiers: NSEvent.ModifierFlags, keyCode: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
        )!
    }

    @Test func theEditingShortcutsAreKnownAndNoOthers() {
        #expect(EditingShortcuts.action(for: press("c", .command, keyCode: kVK_ANSI_C)) == #selector(NSText.copy(_:)))
        #expect(EditingShortcuts.action(for: press("x", .command, keyCode: kVK_ANSI_X)) == #selector(NSText.cut(_:)))
        #expect(EditingShortcuts.action(for: press("v", .command, keyCode: kVK_ANSI_V)) == #selector(NSText.paste(_:)))
        #expect(EditingShortcuts.action(for: press("a", .command, keyCode: kVK_ANSI_A)) == #selector(NSText.selectAll(_:)))
        #expect(EditingShortcuts.action(for: press("z", .command, keyCode: kVK_ANSI_Z)) == Selector(("undo:")))
        #expect(EditingShortcuts.action(for: press("Z", [.command, .shift], keyCode: kVK_ANSI_Z)) == Selector(("redo:")))
        #expect(EditingShortcuts.action(for: press("C", [.command, .shift], keyCode: kVK_ANSI_C)) == nil, "⇧⌘C is Copy Answer")
        #expect(EditingShortcuts.action(for: press("k", .command, keyCode: kVK_ANSI_K)) == nil)
        #expect(EditingShortcuts.action(for: press("c", [], keyCode: kVK_ANSI_C)) == nil)
    }

    /// A panel that has the keyboard, as Meraline's do once they open. A real one can't be made key reliably in a
    /// test: while another app, test run, or person holds the keyboard, macOS may turn the request down.
    final class KeyPanel: EditingPanel {
        override var isKeyWindow: Bool { true }
    }

    /// `panel`, off every screen and never shown, with `text` in it holding the keyboard.
    private func put(_ text: NSTextView, in panel: EditingPanel) {
        panel.setFrame(NSRect(x: -20_000, y: -20_000, width: 200, height: 100), display: false)
        panel.contentView = text
        panel.makeFirstResponder(text)
    }

    private static let style: NSWindow.StyleMask = [.nonactivatingPanel, .borderless, .fullSizeContentView]

    @Test func commandCReachesTheTextInThePanel() {
        let text = RecordingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        text.string = "Copy me"
        let panel = KeyPanel(contentRect: .zero, styleMask: Self.style, backing: .buffered, defer: false)
        put(text, in: panel)

        #expect(panel.performKeyEquivalent(with: press("c", .command, keyCode: kVK_ANSI_C)))
        #expect(panel.performKeyEquivalent(with: press("x", .command, keyCode: kVK_ANSI_X)))
        #expect(panel.performKeyEquivalent(with: press("a", .command, keyCode: kVK_ANSI_A)))
        #expect(text.received == [#selector(NSText.copy(_:)), #selector(NSText.cut(_:)), #selector(NSText.selectAll(_:))])
        #expect(!panel.performKeyEquivalent(with: press("k", .command, keyCode: kVK_ANSI_K)), "other shortcuts go on to the app")
    }

    @Test func aWindowWithoutTheKeyboardLeavesTheTextAlone() {
        let text = RecordingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let panel = EditingPanel(contentRect: .zero, styleMask: Self.style, backing: .buffered, defer: false)
        put(text, in: panel)

        #expect(!panel.isKeyWindow)
        #expect(!panel.performKeyEquivalent(with: press("c", .command, keyCode: kVK_ANSI_C)))
        #expect(text.received.isEmpty)
    }

    @Test func aCommandNothingInTheWindowTakesGoesNowhereElse() {
        let panel = KeyPanel(contentRect: .zero, styleMask: Self.style, backing: .buffered, defer: false)
        panel.contentView = NSView()
        #expect(EditingShortcuts.target(for: #selector(NSText.copy(_:)), in: panel) == nil)
        #expect(!panel.performKeyEquivalent(with: press("c", .command, keyCode: kVK_ANSI_C)))
    }
}
