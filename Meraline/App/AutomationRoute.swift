import Foundation

/// The `meraline://` URL scheme, for Shortcuts, Raycast, scripts, and other apps.
///
///     meraline://ask                    open the window
///     meraline://ask?text=…             open the window with the question filled in
///     meraline://ask?text=…&send=1      fill it in and send it
///     meraline://ask?selection=…        open the window with text to ask about, as if it had been selected
///                                       when the shortcut was pressed; works with text= and send=1
///     meraline://ask?clipboard=1        add what is on the clipboard, as the clipboard button does
///     meraline://ask?screen=1           add a screenshot of the screen the window opens on, as the screen
///                                       button does; send=1 waits for it, and sends only if everything
///                                       asked for came
///     meraline://ask?agent=1            ask an agent (agent=0: an LLM); works with everything above
///     meraline://new                    start a new chat and open the window
///     meraline://play                   open the window with the games showing
///     meraline://play?game=…            start a game, such as oddOneOut or odd-one-out (see `Game(named:)`)
///     meraline://mode?agent=1           switch to Agent and open the window; agent=0 switches to LLM, and
///                                       meraline://mode alone to the other mode
///     meraline://settings               open Settings
///     meraline://settings?pane=…        open Settings on a pane: general, prompt, permissions, updates,
///                                       about, or a provider such as claudeCode (see `SettingsPane(named:)`)
nonisolated enum AutomationRoute: Equatable, Sendable {
    case ask(text: String?, selection: String? = nil, clipboard: Bool = false, screen: Bool = false, mode: ProviderKind? = nil, send: Bool)
    case newChat
    /// A game to start, or nil to show them all.
    case play(game: Game?)
    /// The mode to switch to, or nil for the other one.
    case mode(ProviderKind?)
    case settings(pane: String?)

    static let scheme = "meraline"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }
        func flag(_ name: String) -> Bool {
            Self.flag(value(name)) == true
        }
        /// `agent=1` or `agent=0`; nil when it is missing or neither.
        var mode: ProviderKind? {
            Self.flag(value("agent")).map { $0 ? .agent : .llm }
        }

        switch (url.host() ?? "").lowercased() {
        case "ask", "":
            let text = value("text")?.trimmed ?? ""
            let selection = value("selection")?.trimmed ?? ""
            self = .ask(
                text: text.isEmpty ? nil : text,
                selection: selection.isEmpty ? nil : selection,
                clipboard: flag("clipboard"),
                screen: flag("screen"),
                mode: mode,
                send: flag("send")
            )
        case "new":
            self = .newChat
        case "play":
            self = .play(game: value("game").flatMap(Game.init(named:)))
        case "mode":
            // A value that is neither on nor off would switch to a mode nobody asked for.
            guard value("agent") == nil || mode != nil else { return nil }
            self = .mode(mode)
        case "settings":
            let pane = value("pane")?.trimmed ?? ""
            self = .settings(pane: pane.isEmpty ? nil : pane)
        default:
            return nil
        }
    }

    /// A switch in a query: 1, true, yes, or on; 0, false, no, or off; nil for anything else.
    private static func flag(_ value: String?) -> Bool? {
        switch value?.trimmed.lowercased() {
        case "1", "true", "yes", "on": true
        case "0", "false", "no", "off": false
        default: nil
        }
    }
}

nonisolated extension Game {
    /// A game by the name `meraline://play?game=` uses: its id, such as oddOneOut, or its title, such as
    /// Odd One Out or odd-one-out. Case, spaces, and punctuation don't matter.
    init?(named name: String) {
        func key(_ name: String) -> String {
            String(name.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
        }
        let wanted = key(name)
        guard !wanted.isEmpty,
              let game = Game.allCases.first(where: { key($0.rawValue) == wanted || key($0.title) == wanted }) else { return nil }
        self = game
    }
}
