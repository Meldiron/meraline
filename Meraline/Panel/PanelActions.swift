import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A keyboard shortcut as an action panel shows it and the window's key monitor matches it. Letters match by
/// the character they type, so a shortcut follows the keyboard layout the way the menu bar's do; the other
/// keys match by key code.
nonisolated struct ActionShortcut: Equatable, Sendable {
    enum Key: Equatable, Sendable {
        case character(Character)
        /// + as Zoom In has it: = too, with Shift or without, since + takes Shift on many keyboards, and the
        /// keypad's +.
        case plus
        /// − as Zoom Out has it, the keypad's too.
        case minus
        /// 0 to 9 by the key's place, on the number row or the keypad, whatever the layout types there without ⌘,
        /// as the menu bar's ⌘1 does on an AZERTY or Czech keyboard, where a digit takes Shift.
        case digit(Int)
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

    /// ⌘ and a digit, 0 to 9.
    static func command(digit: Int) -> ActionShortcut {
        ActionShortcut(.digit(digit), .command)
    }

    /// The number row's keys and the keypad's, 0 to 9, by key code.
    private static let digitKeys: [Int: [Int]] = [
        0: [kVK_ANSI_0, kVK_ANSI_Keypad0],
        1: [kVK_ANSI_1, kVK_ANSI_Keypad1], 2: [kVK_ANSI_2, kVK_ANSI_Keypad2], 3: [kVK_ANSI_3, kVK_ANSI_Keypad3],
        4: [kVK_ANSI_4, kVK_ANSI_Keypad4], 5: [kVK_ANSI_5, kVK_ANSI_Keypad5], 6: [kVK_ANSI_6, kVK_ANSI_Keypad6],
        7: [kVK_ANSI_7, kVK_ANSI_Keypad7], 8: [kVK_ANSI_8, kVK_ANSI_Keypad8], 9: [kVK_ANSI_9, kVK_ANSI_Keypad9],
    ]

    /// One keycap per key, modifiers first, in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    var keycaps: [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        switch key {
        case .character(let character): caps.append(String(character).uppercased())
        case .plus: caps.append("+")
        case .minus: caps.append("−")
        case .digit(let digit): caps.append("\(digit)")
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
        guard key == .plus ? pressed.subtracting(.shift) == modifiers : pressed == modifiers else { return false }
        switch key {
        case .character(let character):
            return characters?.lowercased() == String(character).lowercased()
        case .plus:
            return characters == "+" || characters == "=" || keyCode == UInt16(kVK_ANSI_KeypadPlus)
        case .minus:
            return characters == "-" || keyCode == UInt16(kVK_ANSI_KeypadMinus)
        case .digit(let digit):
            return Self.digitKeys[digit]?.contains(Int(keyCode)) == true
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
    /// Copies the diagnostics, for the sparkle's Copy Diagnostics, which shows only when this is set.
    var copyDiagnostics: (() -> Void)?

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

    /// The action a key press runs from anywhere in the window: one of the open chat's, or Stash Draft while
    /// there is no chat.
    func action(forKeyCode keyCode: UInt16, characters: String?, modifiers: ActionShortcut.Modifiers) -> PanelAction? {
        (chatMenu?.actions ?? [stashDraft].compactMap { $0 }).first { action in
            action.shortcut?.matches(keyCode: keyCode, characters: characters, modifiers: modifiers) == true
        }
    }

    private func focusInput() {
        layout.focusRequest += 1
    }

    // MARK: The open chat

    /// The open chat's actions, or nil when there is no chat to act on; a game has them before its first move.
    /// The first is the primary one: Stop while an answer streams, then Copy Answer for a chat, and Hint or End
    /// Game for a game.
    var chatMenu: ActionMenu? {
        guard !session.turns.isEmpty || session.isPlaying else { return nil }
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
                session.usage.record(as: session.lastAnswerKind) { $0.answersInserted += 1 }
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
        // A decision is a word and a number, nothing to tear off.
        if !session.isStreaming, let answer = session.lastAnswer, session.turns.last(where: { !$0.answer.isEmpty })?.isDecision != true {
            let question = session.turns.last { !$0.answer.isEmpty }?.question ?? ""
            copy.append(PanelAction(id: "tearOff", title: "Tear Off Answer", icon: .symbol("macwindow.on.rectangle"), shortcut: .command("t"), keywords: ["note", "float", "keep", "pin"]) { [layout] in
                AnswerNotes.shared.open(answer: answer, question: question, zoom: layout.answerZoom, workspace: session.workspace?.url)
                session.usage.record(as: session.lastAnswerKind) { $0.answersTornOff += 1 }
            })
        }
        let files = fileActions
        let presets = presetActions
        var answer: [PanelAction] = []
        if session.canAskAgain {
            answer.append(PanelAction(id: "askAgain", title: "Ask Again", icon: .symbol("arrow.clockwise"), shortcut: .command("r")) {
                session.askAgain()
                focusInput()
            })
            answer += askAgainElsewhere
        }
        if session.canRewrite {
            answer += Rewrite.allCases.map { rewrite in
                PanelAction(id: "rewrite.\(rewrite.rawValue)", title: rewrite.title, icon: .symbol(rewrite.symbol)) {
                    session.rewrite(rewrite)
                    focusInput()
                }
            }
        }
        let zoom = zoomActions
        var chat = [PanelAction(id: "newChat", title: "New Chat", icon: .symbol("square.and.pencil"), shortcut: .command("n")) {
            if session.reset() { layout.stashNotice += 1 }
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
                ActionSection(id: "changes", actions: changesActions),
                ActionSection(id: "copy", actions: copy),
                ActionSection(id: "files", actions: files),
                ActionSection(id: "answer", actions: answer),
                ActionSection(id: "presets", actions: presets),
                ActionSection(id: "zoom", actions: zoom),
                ActionSection(id: "chat", actions: chat),
                ActionSection(id: "delete", actions: [delete]),
            ].filter { !$0.actions.isEmpty },
            searchPrompt: "Search for actions…",
            marksPrimary: true
        )
    }

    /// The presets of Settings › Prompt, to run on the last answer once it is ready, as a rewrite does
    /// (`ChatSession.run(_:)`): the first nine on ⌘1…⌘9, which the mode toggle gives up meanwhile. Ahead of the
    /// zoom, so ⌘ and the key where a Czech keyboard types + is ⌘1, as in the menu bar.
    private var presetActions: [PanelAction] {
        guard session.canRewrite else { return [] }
        let session = session
        let presets = PromptPreset.runnable(preferences.presets)
        let shortcuts = session.presetShortcuts(among: presets)
        return presets.enumerated().map { index, preset in
            PanelAction(
                id: "preset.\(preset.id)",
                title: preset.title.trimmed.isEmpty ? "Preset \(index + 1)" : preset.title.trimmed,
                icon: .symbol(preset.shownSymbol),
                shortcut: index < shortcuts ? .command(digit: index + 1) : nil,
                keywords: ["preset", "prompt", "answer"]
            ) {
                session.run(preset)
                focusInput()
            }
        }
    }

    /// Whether there are answers to zoom: a chat's, not a game's nor a decision's, once the first one has begun.
    var canZoomAnswers: Bool {
        session.game == nil && session.turns.contains { !$0.answer.isEmpty && !$0.isDecision }
    }

    /// Zoom In, Zoom Out, and Actual Size for the answers, each while it would change something.
    private var zoomActions: [PanelAction] {
        guard canZoomAnswers else { return [] }
        let layout = layout
        let zoom = layout.answerZoom
        return AnswerZoom.Step.allCases.filter(zoom.allows).map { step in
            PanelAction(
                id: step.rawValue,
                title: step.title,
                subtitle: step == .actualSize ? "Answers are at \(zoom.percent)" : nil,
                icon: .symbol(step.symbol),
                shortcut: step.shortcut,
                keywords: step.keywords
            ) {
                layout.zoomAnswers(step)
            }
        }
    }

    /// Show What Changed (⌘D) when the last answer changed the text its question was about, and Show Answer once
    /// the changes show in its place (see `TextChanges`).
    private var changesActions: [PanelAction] {
        guard !session.isStreaming, let turn = session.turns.last(where: { !$0.answer.isEmpty }), turn.changes != nil else { return [] }
        let layout = layout
        let isShowing = layout.answersShowingChanges.contains(turn.id)
        return [PanelAction(
            id: "showChanges",
            title: isShowing ? "Show Answer" : "Show What Changed",
            subtitle: turn.changes?.stats,
            icon: .symbol(isShowing ? "text.alignleft" : "plus.forwardslash.minus"),
            shortcut: .command("d"),
            keywords: ["diff", "changes", "compare", "edits", "corrections", "grammar"]
        ) {
            layout.toggleChanges(of: turn.id)
        }]
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

    /// Ask Again with each other ready provider, this mode's first. The one picked becomes the provider in use,
    /// switching modes when it is of another kind, so a follow-up goes to it too. A decision model answers about
    /// text only, so it is offered when the chat has some.
    private var askAgainElsewhere: [PanelAction] {
        let preferences = preferences
        let session = session
        let active = preferences.activeProvider
        let hasState = session.hasDecisionState
        let kinds = [preferences.mode] + ProviderKind.allCases.filter { $0 != preferences.mode }
        return kinds.flatMap { preferences.readyProviders(for: $0) }.filter { $0 != active && ($0.kind != .decision || hasState) }.map { provider in
            PanelAction(
                id: "askAgainWith.\(provider.rawValue)",
                title: "Ask Again with \(provider.name)",
                subtitle: modelLine(for: provider),
                icon: .symbol(provider.symbol),
                keywords: ["retry", "provider", "model"]
            ) {
                preferences.provider = provider
                session.askAgain()
                focusInput()
            }
        }
    }

    /// What to do with the files an agent handed over last: open each in its app, the first with ⌘O, and show,
    /// copy, or save them all, as the cards under the answer do.
    private var fileActions: [PanelAction] {
        let handed = session.lastPresentedFiles.filter(\.exists)
        guard !handed.isEmpty else { return [] }
        let files = PresentedFiles.shared
        var actions: [PanelAction] = []
        for file in handed where file.opening != .never {
            actions.append(PanelAction(id: "openFile.\(file.id)", title: "Open \(file.name)", icon: .symbol("arrow.up.forward.app"), shortcut: actions.isEmpty ? .command("o") : nil, keywords: ["file"]) {
                files.open(file)
            })
        }
        let them = handed.count == 1 ? handed[0].name : "\(handed.count) Files"
        return actions + [
            PanelAction(id: "showFiles", title: "Show \(them) in Finder", icon: .symbol("folder"), keywords: ["file", "reveal"]) {
                files.showInFinder(handed)
            },
            PanelAction(id: "copyFiles", title: "Copy \(them)", icon: .symbol("doc.on.doc"), keywords: ["file"]) {
                files.copy(handed)
            },
            PanelAction(id: "saveFiles", title: "Save \(them) to Downloads", icon: .symbol("square.and.arrow.down"), shortcut: .command("s"), keywords: ["file", "download"]) {
                files.saveToDownloads(handed)
            },
        ]
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
        } else if !session.turns.isEmpty {
            round.append(PanelAction(id: "restartGame", title: "Restart \(game.title)", icon: .symbol("arrow.counterclockwise"), shortcut: .command("r"), keywords: ["start over", "new game"]) {
                session.restartGame()
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

    /// The sparkle's panel: the ready providers of the current mode, Add Text (the manual context Tab opens),
    /// the other modes, anonymous mode, hiding from screen sharing, Settings, and Copy Diagnostics.
    var providersMenu: ActionMenu {
        let preferences = preferences
        let session = session
        let layout = layout
        let kind = preferences.mode
        let ready = preferences.readyProviders(for: kind)
        let active = preferences.activeProvider
        var providers = ready.map { provider in
            PanelAction(id: "provider.\(provider.rawValue)", title: provider.name, subtitle: modelLine(for: provider), icon: .symbol(provider.symbol), isChecked: provider == active) {
                preferences.provider = provider
                session.prewarm()
                focusInput()
            }
        }
        if ready.isEmpty {
            providers.append(PanelAction(id: "setUp", title: "Set Up \(kind.pluralTitle)…", icon: .symbol("gearshape")) { [openSettings] in
                openSettings(.provider(kind.providers[0]))
            })
        }
        let switches = ProviderKind.allCases.filter { $0 != kind }.map { other in
            let number = (ProviderKind.allCases.firstIndex(of: other) ?? 0) + 1
            return PanelAction(id: "switchMode.\(other.rawValue)", title: "Switch to \(other.title)", icon: .image(other.image), shortcut: .command(Character("\(number)"))) {
                preferences.mode = other
                session.prewarm()
                focusInput()
            }
        }
        let modes = switches + [
            PanelAction(id: "anonymous", title: "Anonymous Mode", subtitle: "Keep chats out of Recent Chats", icon: .symbol("sunglasses"), shortcut: .command("n", .shift), isChecked: session.isAnonymous) {
                session.isAnonymous.toggle()
                focusInput()
            },
            PanelAction(id: "hideFromScreenSharing", title: "Hide from Screen Sharing", subtitle: "Where the recording app allows it", icon: .symbol("eye.slash"), isChecked: preferences.hidesFromScreenSharing) {
                preferences.hidesFromScreenSharing.toggle()
                focusInput()
            },
        ]
        // Manual context, so it is discoverable without knowing the Tab shortcut. Not while a game is on or the
        // card is already open.
        var context: [PanelAction] = []
        if !session.isPlaying, session.typedState == nil {
            context.append(PanelAction(id: "addText", title: "Add Text", subtitle: "Write context to send with your question (Tab)", icon: .symbol("square.and.pencil")) {
                session.writeState()
                layout.stateFocusRequest += 1
            })
        }
        var settings: [PanelAction] = []
        if let active {
            settings.append(PanelAction(id: "providerSettings", title: "\(active.name) Settings…", icon: .symbol("slider.horizontal.3")) { [openSettings] in
                openSettings(.provider(active))
            })
        }
        settings.append(PanelAction(id: "settings", title: "Settings…", icon: .symbol("gearshape"), shortcut: .command(",")) { [openSettings] in
            openSettings(nil)
        })
        if let copyDiagnostics {
            // The same report as Settings › About's and the crash capsule's, at any time.
            settings.append(PanelAction(
                id: "copyDiagnostics",
                title: "Copy Diagnostics",
                subtitle: "No questions, answers, or keys",
                icon: .symbol("stethoscope"),
                keywords: ["bug", "report", "issue", "log", "debug", "support"],
                perform: copyDiagnostics
            ))
        }
        let searchPrompt: String = switch kind {
        case .llm: "Search LLMs and settings…"
        case .agent: "Search agents and settings…"
        case .decision: "Search decision models and settings…"
        }
        var sections = [ActionSection(id: "providers", actions: providers)]
        if !context.isEmpty { sections.append(ActionSection(id: "context", actions: context)) }
        sections.append(ActionSection(id: "modes", actions: modes))
        sections.append(ActionSection(id: "settings", actions: settings))
        return ActionMenu(
            title: kind.pluralTitle,
            sections: sections,
            searchPrompt: searchPrompt
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

    /// Stash Draft, which parks what an empty chat has typed and added in Recent Chats, for 30 minutes like any
    /// chat there; nil while there is nothing to stash (see `ChatSession.canStashDraft`).
    var stashDraft: PanelAction? {
        guard session.canStashDraft else { return nil }
        let session = session
        let layout = layout
        return PanelAction(
            id: "stashDraft",
            title: "Stash Draft",
            subtitle: "Reopen it here within \(Int(ChatSession.chatLifetime / 60)) minutes",
            icon: .symbol("tray.and.arrow.down"),
            shortcut: .command("s"),
            keywords: ["park", "later", "keep", "save"]
        ) {
            session.stashDraft()
            layout.stashNotice += 1
            focusInput()
        }
    }

    /// Stash Draft while there is a draft to stash, the recent chats, newest first, and Clear Recent Chats, which
    /// asks first.
    var historyMenu: ActionMenu {
        let session = session
        let layout = layout
        let chats = session.history.map { chat in
            PanelAction(
                id: "chat.\(chat.id.uuidString)",
                title: chat.title.onOneLine,
                subtitle: chat.isStash ? "Stashed draft" : chat.draft == nil ? nil : "With a draft",
                icon: icon(for: chat),
                detail: chat.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            ) {
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
            sections: [
                ActionSection(id: "stash", actions: [stashDraft].compactMap { $0 }),
                ActionSection(id: "chats", actions: chats),
                ActionSection(id: "clear", actions: clear),
            ],
            searchPrompt: "Search recent chats…",
            emptyText: "No recent chats yet. A chat you close, or a draft you stash with ⌘S, waits here for \(Int(ChatSession.chatLifetime / 60)) minutes."
        )
    }

    private func icon(for chat: ChatSession.PastChat) -> PanelAction.Icon {
        if case .game(let game) = chat.mode { return .symbol(game.symbol) }
        if chat.isStash { return .symbol("tray.full") }
        return chat.workspace == nil ? .symbol("bubble.left") : .image(ProviderKind.agent.image)
    }
}

private extension ActionShortcut {
    /// ⇧⌘⌫. Plain ⌘⌫ stays with the input, where it deletes to the start of the line.
    static let deleteChat = ActionShortcut(.delete, [.command, .shift])
    /// ⌘↵: Return sends a question, and ⌘ sends the answer back where you came from.
    static let insertAnswer = ActionShortcut(.returnKey, .command)
}
