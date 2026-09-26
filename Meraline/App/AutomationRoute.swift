import Foundation

/// The `meraline://` URL scheme, for Shortcuts, Raycast, scripts, and other apps.
///
///     meraline://ask                    open the window
///     meraline://ask?text=…             open the window with the question filled in
///     meraline://ask?text=…&send=1      fill it in and send it
///     meraline://ask?selection=…        open the window with text to ask about, as if it had been selected
///                                       when the shortcut was pressed; works with text= and send=1
///     meraline://new                    start a new chat and open the window
///     meraline://settings               open Settings
///     meraline://settings?pane=…        open Settings on a pane: general, prompt, updates, about, or a
///                                       provider such as claudeCode (see `SettingsPane(named:)`)
nonisolated enum AutomationRoute: Equatable, Sendable {
    case ask(text: String?, selection: String? = nil, send: Bool)
    case newChat
    case settings(pane: String?)

    static let scheme = "meraline"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }

        switch (url.host() ?? "").lowercased() {
        case "ask", "":
            let text = value("text")?.trimmed ?? ""
            let selection = value("selection")?.trimmed ?? ""
            let send = ["1", "true", "yes"].contains((value("send") ?? "").lowercased())
            self = .ask(text: text.isEmpty ? nil : text, selection: selection.isEmpty ? nil : selection, send: send)
        case "new":
            self = .newChat
        case "settings":
            let pane = value("pane")?.trimmed ?? ""
            self = .settings(pane: pane.isEmpty ? nil : pane)
        default:
            return nil
        }
    }
}
