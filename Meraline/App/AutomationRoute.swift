import Foundation

/// The `meraline://` URL scheme, for Shortcuts, Raycast, scripts, and other apps.
///
///     meraline://ask                    open the window
///     meraline://ask?text=…             open the window with the question filled in
///     meraline://ask?text=…&send=1      fill it in and send it
///     meraline://new                    start a new chat and open the window
///     meraline://settings               open Settings
nonisolated enum AutomationRoute: Equatable, Sendable {
    case ask(text: String?, send: Bool)
    case newChat
    case settings

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
            let send = ["1", "true", "yes"].contains((value("send") ?? "").lowercased())
            self = .ask(text: text.isEmpty ? nil : text, send: send)
        case "new":
            self = .newChat
        case "settings":
            self = .settings
        default:
            return nil
        }
    }
}
