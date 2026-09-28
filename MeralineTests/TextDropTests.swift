import AppKit
import SwiftUI
import Testing
@testable import Meraline

/// Text dragged onto the window lands in a card of its own, as a selection does; files and pictures attach.
@MainActor
struct TextDropTests {
    @Test func textIsText() {
        #expect(ClipboardContent.drop(of: ["public.utf8-plain-text"]) == .text)
        #expect(ClipboardContent.drop(of: ["com.apple.webarchive", "public.rtf", "public.html", "public.utf8-plain-text"]) == .text)
    }

    @Test func filesAndPicturesAttachAsBefore() {
        #expect(ClipboardContent.drop(of: ["public.file-url", "public.utf8-plain-text"]) == .file)
        #expect(ClipboardContent.drop(of: ["public.png"]) == .image)
        #expect(ClipboardContent.drop(of: ["public.tiff", "public.utf8-plain-text"]) == .image)
    }

    /// A browser drags a picture with its address, as a link and as text, in whatever order.
    @Test func aWebPagesPictureStaysAPicture() {
        #expect(ClipboardContent.drop(of: ["public.utf8-plain-text", "public.url", "public.url-name", "public.tiff"]) == .image)
        #expect(ClipboardContent.drop(of: ["public.tiff", "public.url", "public.utf8-plain-text"]) == .image)
    }

    /// A word processor drags a picture of the words after the words themselves.
    @Test func wordsBeforeTheirPictureAreText() {
        #expect(ClipboardContent.drop(of: ["public.rtf", "public.utf8-plain-text", "com.adobe.pdf", "public.png"]) == .text)
    }

    @Test func aLinkAloneIsText() {
        #expect(ClipboardContent.drop(of: ["public.url", "public.url-name", "public.utf8-plain-text"]) == .text)
    }

    @Test func passwordsAndUnknownKindsBringNothing() {
        #expect(ClipboardContent.drop(of: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]) == nil)
        #expect(ClipboardContent.drop(of: ["com.apple.webarchive"]) == nil)
        #expect(ClipboardContent.drop(of: []) == nil)
    }

    @Test func handedOverTextIsASelection() throws {
        let selection = try #require(SelectedText.handedOver("  \r\nDragged words\n"))
        #expect(selection.text == "Dragged words")
        #expect(!selection.isFromClipboard)
        #expect(SelectedText.handedOver(" \n ") == nil)
    }

    /// The field being edited takes no drops, so text dropped on the input falls through to the card's drop,
    /// which lies behind it. SwiftUI's field editor signs up for them whenever a field starts editing.
    @Test func theInputLeavesDropsToTheCard() throws {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        let field = try Self.input(in: panel)
        #expect(panel.makeFirstResponder(field))
        let editor = try #require(panel.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)
        #expect(editor.registeredDraggedTypes.isEmpty)

        // Signed up again, as SwiftUI does a moment after a field first starts editing: giving up the keyboard,
        // before anything can be dragged in from another app, takes it off again.
        editor.registerForDraggedTypes([.string, .fileURL])
        panel.resignKey()
        #expect(editor.registeredDraggedTypes.isEmpty)
        #expect(panel.makeFirstResponder(nil))
        #expect(panel.makeFirstResponder(field))
        #expect(editor.registeredDraggedTypes.isEmpty)
    }

    /// In any other window the field being edited takes the text itself.
    @Test func anOrdinaryFieldTakesDropsItself() throws {
        let window = EditingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        let field = try Self.input(in: window)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(!editor.registeredDraggedTypes.isEmpty)
    }

    /// A SwiftUI text field like the panel's input, in `window`, laid out and ready to edit.
    private static func input(in window: NSWindow) throws -> NSTextField {
        let host = NSHostingView(rootView: TextField("Ask anything…", text: .constant("")).frame(width: 300))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 80)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return try #require(textField(in: host))
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }
}
