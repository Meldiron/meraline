import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A keyboard shortcut as an action panel shows it and the window's key monitor matches it. Letters match by
/// the character they type, so a shortcut follows the keyboard layout the way the menu bar's do; the other
/// keys match by key code.
nonisolated struct ActionShortcut: Equatable, Sendable {
    enum Key: Equatable, Sendable {
        case character(Character)
        case delete
        case returnKey
        /// Shown only: Esc belongs to the window's own steps (see `PanelController.handleEscape`).
        case escape
    }

    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) { self.rawValue = rawValue }

        /// The modifiers of a key press that a shortcut can use.
        init(_ flags: NSEvent.ModifierFlags) {
            var modifiers: Modifiers = []
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
            self = modifiers
        }
    }

    let key: Key
    let modifiers: Modifiers

    init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// ⌘ and a letter, with any other modifiers.
    static func command(_ character: Character, _ others: Modifiers = []) -> ActionShortcut {
        ActionShortcut(.character(character), others.union(.command))
    }

    static let escape = ActionShortcut(.escape)
    static let returnKey = ActionShortcut(.returnKey)

    /// One keycap per key, modifiers first, in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    var keycaps: [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        switch key {
        case .character(let character): caps.append(String(character).uppercased())
        case .delete: caps.append("⌫")
        case .returnKey: caps.append("↵")
        case .escape: caps.append("esc")
        }
        return caps
    }

    /// The shortcut in one line, for tooltips: "⇧⌘C".
    var text: String { keycaps.joined() }

    /// Whether a key press is this shortcut. `characters` is the press's `charactersIgnoringModifiers`, which
    /// keeps Shift, so it is compared without case.
    func matches(keyCode: UInt16, characters: String?, modifiers pressed: Modifiers) -> Bool {
        guard pressed == modifiers else { return false }
        switch key {
        case .character(let character):
            return characters?.lowercased() == String(character).lowercased()
        case .delete:
            return keyCode == UInt16(kVK_Delete)
        case .returnKey:
            return keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter)
        case .escape:
            return false
        }
    }
}

/// What a row asks before an action that can't be undone runs.
nonisolated struct ActionConfirmation: Equatable, Sendable {
    let title: String
    let message: String
    /// The label of the button that goes ahead, such as "Delete".
    let button: String
}

/// One row of an action panel: what it says, its shortcut, and what it does.
struct PanelAction: Identifiable {
    enum Icon {
        case symbol(String)
        /// A picture of Meraline's own, such as the robot head of Agent mode.
        case image(Image)
    }

    let id: String
    let title: String
    var subtitle: String?
    var icon: Icon
    var shortcut: ActionShortcut?
    /// Quiet text at the end of the row, such as when a recent chat was.
    var detail: String?
    /// A pink checkmark at the end of the row: the provider in use, or a mode that is on.
    var isChecked = false
    var isDestructive = false
    /// Set for an action that can't be undone: the panel asks first.
    var confirmation: ActionConfirmation?
    /// More words the search finds the row by, such as "paste" for Insert Answer.
    var keywords: [String] = []
    let perform: () -> Void
}

struct ActionSection: Identifiable {
    let id: String
    var actions: [PanelAction]
}

/// The rows an action panel offers, grouped into sections, with the panel's heading and search prompt.
struct ActionMenu {
    let title: String
    let sections: [ActionSection]
    let searchPrompt: String
    /// Said instead of rows when the menu has none at all.
    var emptyText = "Nothing here yet"
    /// Whether the first row is the primary action, marked with ↵, which the footer also offers.
    var marksPrimary = false

    var actions: [PanelAction] { sections.flatMap(\.actions) }

    /// The action the footer offers beside Actions.
    var primary: PanelAction? { actions.first }

    /// The sections with the rows whose title, subtitle, or keywords contain the query, without empty sections.
    func filtered(by query: String) -> [ActionSection] {
        let query = query.trimmed
        return sections.compactMap { section in
            let actions = query.isEmpty ? section.actions : section.actions.filter {
                $0.title.localizedStandardContains(query) || $0.subtitle?.localizedStandardContains(query) == true
                    || $0.keywords.contains { $0.localizedStandardContains(query) }
            }
            return actions.isEmpty ? nil : ActionSection(id: section.id, actions: actions)
        }
    }
}

/// The three panels of actions: the open chat's, behind Actions in the footer and ⌘K; the sparkle's; and the
/// recent chats, behind the clock under the input.
nonisolated enum ActionPanelKind: Hashable, Sendable {
    case chat
    case providers
    case history
}

/// The panel of actions open over the window.
struct ActionPanelRequest: Equatable {
    let kind: ActionPanelKind
    /// The action waiting for a yes, shown in place of the list.
    var confirming: PanelAction.ID?
    /// The panel opened only to confirm, from the action's shortcut, so Cancel closes it.
    var isConfirmationOnly = false
}

/// What the actions reach: the chat, the settings, the window's layout, and the Settings window. The footer,
/// the three panels, and the window's key monitor all build their actions here, so a shortcut does the same
/// wherever it is pressed.
struct PanelContext {
    let session: ChatSession
    let preferences: Preferences
    let layout: PanelLayout
    let openSettings: (SettingsPane?) -> Void
    /// Insert Answer's way into the app in front, or nil when there is none, as when Meraline itself is.
    var insertion: AnswerInsertion?

    func menu(for kind: ActionPanelKind) -> ActionMenu? {
        switch kind {
        case .chat: chatMenu
        case .providers: providersMenu
        case .history: historyMenu
        }
    }

    /// Runs an action from a panel or its shortcut, or asks first when it can't be undone.
    func run(_ action: PanelAction, in kind: ActionPanelKind, fromShortcut: Bool = false) {
        if action.confirmation != nil {
            let isOpen = layout.actionPanel?.kind == kind
            layout.actionPanel = ActionPanelRequest(kind: kind, confirming: action.id, isConfirmationOnly: fromShortcut && !isOpen)
            return
        }
        if layout.actionPanel != nil { layout.closeActionPanel() }
        action.perform()
    }

    /// Runs an action the user said yes to.
    func confirm(_ action: PanelAction) {
        layout.closeActionPanel()
        action.perform()
    }

    /// The action a key press runs from anywhere in the window: one of the open chat's.
    func action(forKeyCode keyCode: UInt16, characters: String?, modifiers: ActionShortcut.Modifiers) -> PanelAction? {
        chatMenu?.actions.first { action in
            action.shortcut?.matches(keyCode: keyCode, characters: characters, modifiers: modifiers) == true
        }
    }

    private func focusInput() {
        layout.focusRequest += 1
    }

    // MARK: The open chat

    /// The open chat's actions, or nil when there is no chat to act on. The first is the primary one: Stop while
    /// an answer streams, then Copy Answer for a chat, and Hint or End Game for a game.
    var chatMenu: ActionMenu? {
        guard !session.turns.isEmpty else { return nil }
        return session.game.map(gameMenu) ?? questionMenu
    }

    private var questionMenu: ActionMenu {
        let session = session
        var primary: [PanelAction] = []
        var copy: [PanelAction] = []
        if session.isStreaming {
            primary.append(stop)
            if session.lastAnswer != nil { copy.append(copyAnswer) }
        } else if session.lastAnswer != nil {
            primary.append(copyAnswer)
        }
        if !session.isStreaming, session.lastAnswer != nil, let insertion {
            copy.append(PanelAction(
                id: "insertAnswer",
                title: "Insert Answer into \(insertion.appName)",
                subtitle: insertion.canPaste ? nil : "Copies it: pasting needs Accessibility access",
                icon: .symbol("text.insert"),
                // Not while a follow-up is being typed: ⌘↵ there would close the window over it.
                shortcut: session.draft.trimmed.isEmpty ? .insertAnswer : nil,
                keywords: ["paste", "cursor"]
            ) {
                guard let answer = session.lastAnswer else { return }
                insertion.insert(answer)
            })
        }
        if !session.isStreaming, let answer = session.lastAnswer {
            copy += codeBlockActions(in: answer)
        }
        if session.conversationMarkdown != nil {
            copy.append(PanelAction(id: "copyConversation", title: "Copy Conversation", icon: .symbol("doc.on.clipboard"), shortcut: .command("c", [.shift, .option])) {
                session.copyConversation()
                layout.copyNotice += 1
            })
        }
        var answer: [PanelAction] = []
        if session.canAskAgain {
            answer.append(PanelAction(id: "askAgain", title: "Ask Again", icon: .symbol("arrow.clockwise"), shortcut: .command("r")) {
                session.askAgain()
                focusInput()
            })
        }
        if session.canRewrite {
            answer += Rewrite.allCases.map { rewrite in
                PanelAction(id: "rewrite.\(rewrite.rawValue)", title: rewrite.title, icon: .symbol(rewrite.symbol)) {
                    session.rewrite(rewrite)
                    focusInput()
                }
            }
        }
        var chat = [PanelAction(id: "newChat", title: "New Chat", icon: .symbol("square.and.pencil"), shortcut: .command("n")) {
            session.reset()
            focusInput()
        }]
        if let workspace = session.workspace {
            chat.append(PanelAction(id: "showWorkspace", title: "Show Agent’s Files in Finder", icon: .symbol("folder"), shortcut: .command("o", .shift)) {
                Log.panel.info("Showing the chat's workspace in Finder")
                NSWorkspace.shared.open(workspace.url)
            })
        }
        let delete = PanelAction(
            id: "deleteChat",
            title: "Delete Chat",
            icon: .symbol("trash"),
            shortcut: .deleteChat,
            isDestructive: true,
            confirmation: ActionConfirmation(
                title: "Delete this chat?",
                message: session.workspace == nil
                    ? "It won’t go to Recent Chats. This can’t be undone."
                    : "It won’t go to Recent Chats, and the files its agent made go with it. This can’t be undone.",
                button: "Delete"
            )
        ) {
            session.deleteChat()
            focusInput()
        }
        return ActionMenu(
            title: session.turns.first.map { $0.question.isEmpty ? "This Chat" : $0.question.onOneLine } ?? "This Chat",
            sections: [
                ActionSection(id: "primary", actions: primary),
                ActionSection(id: "copy", actions: copy),
                ActionSection(id: "answer", actions: answer),
                ActionSection(id: "chat", actions: chat),
                ActionSection(id: "delete", actions: [delete]),
            ].filter { !$0.actions.isEmpty },
            searchPrompt: "Search for actions…",
            marksPrimary: true
        )
    }

    /// Copy Code Block for each block of code in the last answer, up to nine, with its language and first line.
    private func codeBlockActions(in answer: String) -> [PanelAction] {
        let blocks = Array(MarkdownBlock.codeBlocks(in: answer).filter { !$0.code.trimmed.isEmpty }.prefix(9))
        return blocks.enumerated().map { index, block in
            let firstLine = block.code.split(separator: "\n").first.map { String($0).trimmed } ?? ""
            let subtitle = [block.language ?? "", firstLine].filter { !$0.isEmpty }.joined(separator: " · ")
            return PanelAction(
                id: "copyCode.\(index)",
                title: blocks.count == 1 ? "Copy Code Block" : "Copy Code Block \(index + 1)",
                subtitle: subtitle.isEmpty ? nil : subtitle,
                icon: .symbol("chevron.left.forwardslash.chevron.right"),
                keywords: ["code", "snippet"]
            ) { [layout] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(block.code, forType: .string)
                Log.panel.info("Code block copied")
                layout.copyNotice += 1
            }
        }
    }

    private func gameMenu(_ game: Game) -> ActionMenu {
        let session = session
        let hint = PanelAction(id: "hint", title: "Hint", icon: .symbol("lightbulb"), shortcut: .command("i")) {
            session.hint()
            focusInput()
        }
        let endGame = PanelAction(id: "endGame", title: "End Game", icon: .symbol("flag.checkered"), shortcut: .command("n")) {
            session.reset()
            focusInput()
        }
        var primary: [PanelAction] = []
        var round: [PanelAction] = []
        var end: [PanelAction] = []
        if session.isStreaming {
            primary.append(stop)
            end.append(endGame)
        } else if session.canHint {
            primary.append(hint)
            end.append(endGame)
        } else {
            primary.append(endGame)
        }
        if let rematch = session.rematch, !rematch.isAfterGame {
            round.append(PanelAction(id: "playAgain", title: "Play Again", icon: .symbol("arrow.counterclockwise"), shortcut: .command("r")) {
                session.playAgain()
                focusInput()
            })
        }
        if session.conversationMarkdown != nil {
            round.append(PanelAction(id: "copyGame", title: "Copy Game", icon: .symbol("doc.on.clipboard"), shortcut: .command("c", .shift)) {
                session.copyConversation()
                layout.copyNotice += 1
            })
        }
        let delete = PanelAction(
            id: "deleteGame",
            title: "Delete Game",
            icon: .symbol("trash"),
            shortcut: .deleteChat,
            isDestructive: true,
            confirmation: ActionConfirmation(title: "Delete this game?", message: "It won’t go to Recent Chats. The score against the model stays.", button: "Delete")
        ) {
            session.deleteChat()
            focusInput()
        }
        return ActionMenu(
            title: game.title,
            sections: [
                ActionSection(id: "primary", actions: primary),
                ActionSection(id: "round", actions: round),
                ActionSection(id: "end", actions: end),
                ActionSection(id: "delete", actions: [delete]),
            ].filter { !$0.actions.isEmpty },
            searchPrompt: "Search for actions…",
            marksPrimary: true
        )
    }

    private var stop: PanelAction {
        PanelAction(id: "stop", title: "Stop", icon: .symbol("stop.circle"), shortcut: .escape) { [session] in
            session.stop()
            focusInput()
        }
    }

    private var copyAnswer: PanelAction {
        PanelAction(id: "copyAnswer", title: "Copy Answer", icon: .symbol("doc.on.doc"), shortcut: .command("c", .shift)) { [session, layout] in
            session.copyLastAnswer()
            layout.copyNotice += 1
        }
    }

    // MARK: The sparkle

    /// The sparkle's panel: the ready providers of the current mode, the other mode, anonymous mode, hiding
    /// from screen sharing, and Settings.
    var providersMenu: ActionMenu {
        let preferences = preferences
        let session = session
        let kind = preferences.mode
        let ready = preferences.readyProviders(for: kind)
        let active = preferences.activeProvider
        var providers = ready.map { provider in
            PanelAction(id: "provider.\(provider.rawValue)", title: provider.name, subtitle: modelLine(for: provider), icon: .symbol(provider.symbol), isChecked: provider == active) {
                preferences.provider = provider
                if provider.isOnDevice { AppleIntelligenceClient.prewarm() }
                focusInput()
            }
        }
        if ready.isEmpty {
            providers.append(PanelAction(id: "setUp", title: "Set Up \(kind.pluralTitle)…", icon: .symbol("gearshape")) { [openSettings] in
                openSettings(.provider(kind.providers[0]))
            })
        }
        let other: ProviderKind = kind == .llm ? .agent : .llm
        let number = (ProviderKind.allCases.firstIndex(of: other) ?? 0) + 1
        let modes = [
            PanelAction(id: "switchMode", title: "Switch to \(other.title)", icon: .image(other.image), shortcut: .command(Character("\(number)"))) {
                preferences.mode = other
                if preferences.activeProvider?.isOnDevice == true { AppleIntelligenceClient.prewarm() }
                focusInput()
            },
            PanelAction(id: "anonymous", title: "Anonymous Mode", subtitle: "Keep chats out of Recent Chats", icon: .symbol("sunglasses"), shortcut: .command("n", .shift), isChecked: session.isAnonymous) {
                session.isAnonymous.toggle()
                focusInput()
            },
            PanelAction(id: "hideFromScreenSharing", title: "Hide from Screen Sharing", subtitle: "Where the recording app allows it", icon: .symbol("eye.slash"), isChecked: preferences.hidesFromScreenSharing) {
                preferences.hidesFromScreenSharing.toggle()
                focusInput()
            },
        ]
        var settings: [PanelAction] = []
        if let active {
            settings.append(PanelAction(id: "providerSettings", title: "\(active.name) Settings…", icon: .symbol("slider.horizontal.3")) { [openSettings] in
                openSettings(.provider(active))
            })
        }
        settings.append(PanelAction(id: "settings", title: "Settings…", icon: .symbol("gearshape"), shortcut: .command(",")) { [openSettings] in
            openSettings(nil)
        })
        return ActionMenu(
            title: kind.pluralTitle,
            sections: [
                ActionSection(id: "providers", actions: providers),
                ActionSection(id: "modes", actions: modes),
                ActionSection(id: "settings", actions: settings),
            ],
            searchPrompt: kind == .llm ? "Search LLMs and settings…" : "Search agents and settings…"
        )
    }

    /// The model a provider answers with, and how many MCP servers an agent may use.
    private func modelLine(for provider: Provider) -> String {
        let settings = preferences[provider]
        let model = settings.model.isEmpty ? "Default model" : settings.model
        let servers = settings.allowedMCPServers.count
        return servers > 0 ? "\(model) · \(servers) MCP server\(servers == 1 ? "" : "s")" : model
    }

    // MARK: Recent chats

    /// The recent chats, newest first, and Clear Recent Chats, which asks first.
    var historyMenu: ActionMenu {
        let session = session
        let layout = layout
        let chats = session.history.map { chat in
            PanelAction(id: "chat.\(chat.id.uuidString)", title: chat.title.onOneLine, icon: icon(for: chat), detail: chat.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))) {
                session.reopen(chat.id)
                focusInput()
            }
        }
        var clear: [PanelAction] = []
        if !chats.isEmpty {
            let count = chats.count
            clear.append(PanelAction(
                id: "clearHistory",
                title: "Clear Recent Chats",
                icon: .symbol("trash"),
                isDestructive: true,
                confirmation: ActionConfirmation(
                    title: count == 1 ? "Clear 1 recent chat?" : "Clear \(count) recent chats?",
                    message: "\(count == 1 ? "It’s" : "They’re") forgotten for good, with any files an agent made. The open chat stays.",
                    button: "Clear"
                )
            ) {
                let forgot = session.forgetHistory()
                Log.panel.info("Recent chats cleared: \(forgot)")
                layout.noteForgotten(forgot)
                focusInput()
            })
        }
        return ActionMenu(
            title: "Recent Chats",
            sections: [ActionSection(id: "chats", actions: chats), ActionSection(id: "clear", actions: clear)],
            searchPrompt: "Search recent chats…",
            emptyText: "No recent chats yet. A chat you close waits here until Meraline quits."
        )
    }

    private func icon(for chat: ChatSession.PastChat) -> PanelAction.Icon {
        if case .game(let game) = chat.mode { return .symbol(game.symbol) }
        return chat.workspace == nil ? .symbol("bubble.left") : .image(ProviderKind.agent.image)
    }
}

private extension ActionShortcut {
    /// ⇧⌘⌫. Plain ⌘⌫ stays with the input, where it deletes to the start of the line.
    static let deleteChat = ActionShortcut(.delete, [.command, .shift])
    /// ⌘↵: Return sends a question, and ⌘ sends the answer back where you came from.
    static let insertAnswer = ActionShortcut(.returnKey, .command)
}
