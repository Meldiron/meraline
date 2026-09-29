import AppKit
import SwiftUI

/// The panel's text fields keep to one line that scrolls sideways, like Spotlight or Raycast. A line
/// break shows there as ⏎ and is a line break again in what you send, so pasted code keeps its lines.
nonisolated extension String {
    static let lineBreakMark: Character = "⏎"

    /// The text as a one-line field shows it.
    var onOneLine: String {
        split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .joined(separator: String(Self.lineBreakMark))
    }

    /// The text of a one-line field, its marks turned back into line breaks.
    var withLineBreaks: String {
        split(omittingEmptySubsequences: false) { $0.isNewline || $0 == Self.lineBreakMark }
            .joined(separator: "\n")
    }
}

extension Binding<String> {
    /// The text for a one-line field: line breaks show as ⏎ and come back when the field changes.
    var onOneLine: Binding<String> {
        Binding(get: { wrappedValue.onOneLine }, set: { wrappedValue = $0.withLineBreaks })
    }
}

extension NSTextView {
    /// Pastes text with line breaks into the field being edited with each break as ⏎. SwiftUI does not
    /// refresh a field while you edit it, so a plain paste would leave the field showing only the last line.
    func pasteOnOneLine(from pasteboard: NSPasteboard) -> Bool {
        guard isFieldEditor, isEditable,
              let text = pasteboard.string(forType: .string), text.contains(where: \.isNewline) else { return false }
        insertText(text.onOneLine, replacementRange: selectedRange())
        return true
    }
}

extension NSWindow {
    /// Fits the view that clips the text of the field being edited back into the field, when it has outgrown it.
    /// AppKit starts editing over whenever a field's placeholder changes, and when its text changed in the same
    /// update, as stashing a draft about a selection empties the input and has it ask anything again, it sizes that
    /// view to the text that was there. Text wider than the field then ran past it, under the pin and the gear and
    /// off the card, and never scrolled. AppKit fits that view to the field whenever the field changes size, so the
    /// field grows by a point and back; starting its editing over again would leave the old view behind, empty.
    func refitFieldBeingEdited() {
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor,
              let field = editor.delegate as? NSTextField, let clip = editor.superview as? NSClipView,
              clip.frame.width > field.bounds.width + 8 // the focus ring's room
        else { return }
        let size = field.frame.size
        field.setFrameSize(NSSize(width: size.width + 1, height: size.height))
        field.setFrameSize(size)
        editor.scrollRangeToVisible(editor.selectedRange())
    }
}
