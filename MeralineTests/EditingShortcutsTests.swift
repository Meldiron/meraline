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

    @Test func commandCReachesTheTextInThePanel() throws {
        let panel = FloatingPanel(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 200, height: 100),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false
        )
        let text = RecordingTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        text.string = "Copy me"
        panel.contentView = text
        panel.orderFrontRegardless()
        panel.makeKey()
        defer { panel.orderOut(nil) }
        try #require(panel.isKeyWindow)
        panel.makeFirstResponder(text)
        text.selectAll(nil)
        text.received = []

        #expect(panel.performKeyEquivalent(with: press("c", .command, keyCode: kVK_ANSI_C)))
        #expect(panel.performKeyEquivalent(with: press("x", .command, keyCode: kVK_ANSI_X)))
        #expect(panel.performKeyEquivalent(with: press("a", .command, keyCode: kVK_ANSI_A)))
        #expect(text.received == [#selector(NSText.copy(_:)), #selector(NSText.cut(_:)), #selector(NSText.selectAll(_:))])
        #expect(!panel.performKeyEquivalent(with: press("k", .command, keyCode: kVK_ANSI_K)), "other shortcuts go on to the app")
    }
}
