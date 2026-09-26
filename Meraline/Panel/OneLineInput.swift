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
