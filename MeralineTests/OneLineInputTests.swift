import AppKit
import SwiftUI
import Testing
@testable import Meraline

@MainActor
struct OneLineInputTests {
    @Test func showsLineBreaksAsMarks() {
        #expect("def f(x):\n    return x\r\nprint(f(3))".onOneLine == "def f(x):⏎    return x⏎print(f(3))")
    }

    @Test func marksComeBackAsLineBreaks() {
        #expect("one⏎two⏎⏎three".withLineBreaks == "one\ntwo\n\nthree")
    }

    @Test func textWithoutLineBreaksStaysAsItIs() {
        let question = "How many digits 8 are there in all numbers from 1 to 1 billion?"
        #expect(question.onOneLine == question)
        #expect(question.withLineBreaks == question)
        #expect("".onOneLine.isEmpty)
    }

    @Test func bindingKeepsTheDraftsLineBreaks() {
        var draft = "first\nsecond"
        let field = Binding(get: { draft }, set: { draft = $0 }).onOneLine
        #expect(field.wrappedValue == "first⏎second")
        field.wrappedValue = "first⏎second⏎third"
        #expect(draft == "first\nsecond\nthird")
        field.wrappedValue = "pasted\nstraight in"
        #expect(draft == "pasted\nstraight in")
    }

    @Test func pastesLineBreaksAsMarksAtTheCaret() {
        let pasteboard = NSPasteboard(name: .init("OneLineInputTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("A\nB", forType: .string)

        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.string = "hello world"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(editor.pasteOnOneLine(from: pasteboard))
        #expect(editor.string == "helloA⏎B world")

        pasteboard.clearContents()
        pasteboard.setString("no breaks", forType: .string)
        #expect(!editor.pasteOnOneLine(from: pasteboard))
    }

    /// Stashing a draft about a selection empties the input and has it ask anything again, and AppKit then sized the
    /// view that clips the input's text to the text that was there. The next long text, such as a preset's, ran
    /// under the pin and the gear and off the card, and never scrolled.
    @Test func theInputClipsItsTextOnceItsPlaceholderChanged() async throws {
        let suite = "OneLineInputTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ShortcutSetup.chosenKey) // the chat, not the shortcut picker
        let preferences = GameTestSupport.preferences()
        let session = GameTestSupport.session(ScriptedModel(["It reads fine."]))
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: Updater(preferences: preferences, defaults: defaults), updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        defer { withExtendedLifetime(controller) {} }
        let panel = try #require(NSApp.windows.first { $0 is FloatingPanel && !before.contains(ObjectIdentifier($0)) })
        try await Task.sleep(for: .milliseconds(300))
        let input = panel.contentView.flatMap(Self.editableField)
        let field = try #require(input)
        #expect(panel.makeFirstResponder(field))

        session.bring(try #require(SelectedText("Hellou how a reu?", appName: "Zed")))
        session.draft = String(repeating: "Fix the grammar of this text without changing its wording. ", count: 3)
        try await Task.sleep(for: .milliseconds(300))
        session.stashDraft()
        try await Task.sleep(for: .milliseconds(300))
        let presets = PromptPreset.defaults(in: .english)
        session.apply(presets[0], among: presets)
        try await Task.sleep(for: .milliseconds(300))

        let editor = try #require(panel.firstResponder as? NSTextView)
        let clip = try #require(editor.superview as? NSClipView)
        #expect(clip.frame.width <= field.bounds.width + 8, "the view clipping the input is \(clip.frame.width) wide, the input \(field.bounds.width)")
        #expect(field.subviews.filter { $0 is NSClipView } == [clip], "no view that clipped it before is left behind")
    }

    private static func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap(editableField).first
    }
}
