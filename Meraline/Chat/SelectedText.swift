import Foundation

/// Text selected in another app, brought along as context for the next question. The shortcut reads it from
/// the app in front (see `SelectionReader`); the Services menu and `meraline://ask?selection=…` hand it over.
/// It waits in the draft, in a card above the row under the input, and goes with the question when it is
/// sent: the model reads it in a `<selected_text>` block before the question. It lives only in memory, like
/// the rest of the chat.
nonisolated struct SelectedText: Identifiable, Equatable, Sendable {
    /// The most that comes along. A stray ⌘A on a long document is cut here rather than filling the question.
    static let limit = 20_000

    let id = UUID()
    let text: String
    /// The app it was selected in, when known.
    let appName: String?
    /// Where that app is, for its icon.
    let appURL: URL?
    /// The selection ran past `limit` and was cut there.
    let isShortened: Bool
    /// Copied rather than selected: the clipboard button above the window brought it.
    let isFromClipboard: Bool

    /// The selection with its ends trimmed and plain line breaks, or nil when nothing is left of it.
    init?(_ text: String, appName: String? = nil, appURL: URL? = nil, fromClipboard: Bool = false) {
        let text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmed
        guard !text.isEmpty else { return nil }
        self.text = String(text.prefix(Self.limit))
        isShortened = text.count > Self.limit
        let appName = appName?.trimmed ?? ""
        self.appName = appName.isEmpty ? nil : appName
        self.appURL = appURL
        isFromClipboard = fromClipboard
    }

    /// Text from the clipboard, for the clipboard button.
    static func clipboard(_ text: String) -> SelectedText? {
        SelectedText(text, appName: "Clipboard", fromClipboard: true)
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// The selection on one line, for the title of a chat in Recent Chats.
    var excerpt: String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// The selection as a Markdown quote, for copying the conversation.
    var markdownQuote: String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }

    /// The same text from the same kind of place, whenever it was read: selecting it again, or copying it
    /// again, brings nothing new.
    func isSame(as other: SelectedText) -> Bool {
        text == other.text && isFromClipboard == other.isFromClipboard
    }

    /// What the model reads for a question about `selection`: the selection in a block that names its app,
    /// or a `<clipboard>` block for copied text, then the question. On its own, the block asks the model to
    /// make sense of the text. Without a selection, the question as it is.
    static func message(_ question: String, about selection: SelectedText?) -> String {
        message(question, about: selection.map { [$0] } ?? [])
    }

    /// The same for several texts: a block for each, in order, then the question.
    static func message(_ question: String, about selections: [SelectedText]) -> String {
        let blocks = selections.map { selection in
            let source = selection.appName.map { " from=\"\($0.replacingOccurrences(of: "\"", with: "'"))\"" } ?? ""
            return selection.isFromClipboard
                ? "<clipboard>\n\(selection.text)\n</clipboard>"
                : "<selected_text\(source)>\n\(selection.text)\n</selected_text>"
        }
        return (blocks + [question]).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
