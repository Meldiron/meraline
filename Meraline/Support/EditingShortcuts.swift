import AppKit

/// Cut, Copy, Paste, Select All, Undo, and Redo for the text in Meraline's own windows, sent straight to whatever
/// has the keyboard. The Edit menu has them too, but the panel takes the keyboard without making Meraline the app
/// in front, and there ⌘C and the rest never reached the text. So each window runs them itself, before any menu
/// is asked, whether Meraline is in front or not.
enum EditingShortcuts {
    /// The editing command a key press asks for, if it asks for one.
    static func action(for event: NSEvent) -> Selector? {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
        case ([.command], "x"): return #selector(NSText.cut(_:))
        case ([.command], "c"): return #selector(NSText.copy(_:))
        case ([.command], "v"): return #selector(NSText.paste(_:))
        case ([.command], "a"): return #selector(NSText.selectAll(_:))
        case ([.command], "z"): return Selector(("undo:"))
        case ([.command, .shift], "z"): return Selector(("redo:"))
        default: return nil
        }
    }

    /// Sends the command to the window's first responder, or whatever takes it after it. False when the press is
    /// no editing command or nothing there takes it, so the rest of the app can have it.
    static func perform(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard window.isKeyWindow, let action = action(for: event), let target = target(for: action, in: window) else {
            return false
        }
        return NSApp.sendAction(action, to: target, from: window)
    }

    /// What in the window takes `action`: its first responder or one after it, up to the window and its delegate,
    /// asking each for a supplemental target as AppKit's own lookup does. Never another window's: a lookup without a
    /// target goes on to the main window, which can be Settings while the panel has the keyboard.
    static func target(for action: Selector, in window: NSWindow) -> Any? {
        var responder = window.firstResponder
        while let current = responder {
            if current.responds(to: action) { return current }
            if let supplemental = current.supplementalTarget(forAction: action, sender: window) { return supplemental }
            responder = current.nextResponder
        }
        if let delegate = window.delegate as? NSObject, delegate.responds(to: action) { return delegate }
        return nil
    }
}

/// A window whose editing shortcuts work in front or not (see `EditingShortcuts`).
class EditingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event) || EditingShortcuts.perform(event, in: self)
    }
}

/// A panel whose editing shortcuts work while another app is in front, as the panel's always is.
class EditingPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event) || EditingShortcuts.perform(event, in: self)
    }
}
