import AppKit

/// Text selected in another app, brought along as context for the next question. The shortcut reads it from
/// the app in front (see `SelectionReader`); a drag onto the window, the Services menu, and
/// `meraline://ask?selection=…` hand it over, and in Decision mode it can be written in the window itself
/// (`typed`), for a decision about text that is nowhere else.
/// It waits in the draft, in a card above the row under the input, and goes with the question when it is
/// sent: the model reads it in a `<selected_text>` block before the question. It lives only in memory, like
/// the rest of the chat.
nonisolated struct SelectedText: Identifiable, Equatable, Sendable {
    /// The most that comes along. A runaway selection is cut here rather than filling the question, but the
    /// cap is high enough that ordinary documents pasted or selected whole still arrive in full.
    static let limit = 1_000_000

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
    /// Written in the window itself, for a decision (see `TypedStateCard`).
    let isTyped: Bool

    /// The selection with its ends trimmed and plain line breaks, or nil when nothing is left of it.
    init?(_ text: String, appName: String? = nil, appURL: URL? = nil, fromClipboard: Bool = false, typed: Bool = false) {
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
        isTyped = typed
    }

    /// Text from the clipboard, for the clipboard button.
    static func clipboard(_ text: String) -> SelectedText? {
        SelectedText(text, appName: "Clipboard", fromClipboard: true)
    }

    /// Text written in the window for a decision.
    static func typed(_ text: String) -> SelectedText? {
        SelectedText(text, typed: true)
    }

    /// Where the text came from, as its card and its quote say: the app, the clipboard, or, for text written in
    /// the window as context for a decision, Context.
    var sourceLabel: String {
        appName ?? (isTyped ? "Context" : "Selected text")
    }

    /// Text another app handed over, dragged onto the window or sent through the Services menu, named after the
    /// app in front: the one it came from, since the panel never brings Meraline to the front. While Meraline
    /// itself is in front, it names none.
    @MainActor
    static func handedOver(_ text: String) -> SelectedText? {
        let app = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0
        }
        return SelectedText(text, appName: app?.localizedName, appURL: app?.bundleURL)
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// How long the text is, as its card and its quote say it: the words, or that only the first `limit`
    /// characters came.
    var lengthLabel: String {
        if isShortened { return "first \(Self.limit.formatted()) characters" }
        return "\(wordCount.formatted()) \(wordCount == 1 ? "word" : "words")"
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
        text == other.text && isFromClipboard == other.isFromClipboard && isTyped == other.isTyped
    }

    /// What the model reads for a question about `selection`: the selection in a block that names its app,
    /// a `<clipboard>` block for copied text, or a `<text>` block for text written in the window, then the
    /// question. On its own, the block asks the model to make sense of the text. Without a selection, the
    /// question as it is.
    static func message(_ question: String, about selection: SelectedText?) -> String {
        message(question, about: selection.map { [$0] } ?? [])
    }

    /// The same for several texts: a block for each, in order, then the question.
    static func message(_ question: String, about selections: [SelectedText]) -> String {
        let blocks = selections.map { selection in
            let source = selection.appName.map { " from=\"\($0.replacingOccurrences(of: "\"", with: "'"))\"" } ?? ""
            if selection.isFromClipboard { return "<clipboard>\n\(selection.text)\n</clipboard>" }
            if selection.isTyped { return "<text>\n\(selection.text)\n</text>" }
            return "<selected_text\(source)>\n\(selection.text)\n</selected_text>"
        }
        return (blocks + [question]).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
