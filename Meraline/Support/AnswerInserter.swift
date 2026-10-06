import AppKit
import ApplicationServices

/// Insert Answer, from the chat's actions (⌘↵): the last answer goes in at the cursor of the app the window was
/// opened over, so a quick "rewrite this" ends where the text was.
///
/// The window never took being the app in front away from that app, so closing it hands the keyboard straight
/// back. Then the app's own Paste command pastes the answer, or ⌘V when its menu has none that looks
/// available, and the clipboard is put back as it was. The answer is marked transient on the clipboard
/// meanwhile, so clipboard managers leave it out. Pasting takes Accessibility access, as reading the selection
/// does; without it the answer is only copied, for you to paste.
final class AnswerInserter {
    /// How long the app in front takes to get the keyboard back once the window is gone.
    private static let focusWait: Duration = .milliseconds(150)
    /// How long the app has to read the clipboard before it is put back. Electron apps read a beat late.
    private static let pasteWait: Duration = .milliseconds(500)
    /// nspasteboard.org's mark for clipboard contents that are about to be put back, as a text expander's are.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Closes the window, which gives the keyboard back to the app in front.
    var closeWindow: () -> Void = {}

    /// Insert Answer as the app in front offers it now, or nil when that is Meraline itself or nothing.
    var insertion: AnswerInsertion? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return AnswerInsertion(appName: app.localizedName ?? "the App", canPaste: SelectionAccess.shared.isGranted) { [weak self] text in
            self?.insert(text, into: app)
        }
    }

    private func insert(_ text: String, into app: NSRunningApplication) {
        let text = text.trimmed
        let name = app.localizedName ?? "the app in front"
        let pasteboard = NSPasteboard.general
        SelectionAccess.shared.refresh()
        guard SelectionAccess.shared.isGranted else {
            AnswerExport.copy(text, to: pasteboard)
            Log.panel.info("Answer copied for \(name): no Accessibility access to paste it")
            closeWindow()
            return
        }

        // The answer's Markdown, and the same answer as HTML and RTF, so an app that takes rich text pastes
        // bold, lists, code, and tables as such (see `AnswerExport`).
        let saved = SelectionReader.snapshot(of: pasteboard)
        let item = NSPasteboardItem()
        AnswerExport.write(text, to: item)
        item.setData(Data(), forType: Self.transientType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let written = pasteboard.changeCount
        closeWindow()

        Task {
            try? await Task.sleep(for: Self.focusWait)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                Log.panel.info("Insert Answer: \(name) is no longer in front, so the answer stays on the clipboard")
                return
            }
            guard let method = Self.paste(in: app) else {
                Log.panel.error("Insert Answer: couldn’t paste into \(name), so the answer stays on the clipboard")
                return
            }
            Log.panel.info("Answer inserted into \(name) through \(method), \(text.count) characters")
            try? await Task.sleep(for: Self.pasteWait)
            // Anything copied since is yours, and stays.
            if pasteboard.changeCount == written { SelectionReader.restore(saved, to: pasteboard) }
        }
    }

    /// Pastes in the app with the Paste command in its menu, or else ⌘V, and says which.
    private static func paste(in app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        if let item = SelectionReader.commandMenuItem("v", in: element),
           AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
            return "the app's Paste command"
        }
        return SelectionReader.pressCommand("v") ? "⌘V" : nil
    }
}

/// Insert Answer's way into the app in front (see `AnswerInserter`), as the chat's actions see it.
struct AnswerInsertion {
    /// The app the answer goes into, for the action's title.
    let appName: String
    /// Whether Meraline may paste the answer; without Accessibility access it is only copied.
    let canPaste: Bool
    let insert: (String) -> Void
}
