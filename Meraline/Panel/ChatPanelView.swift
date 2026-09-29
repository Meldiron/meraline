import SwiftUI
import UniformTypeIdentifiers

struct ChatPanelView: View {
    /// How long the card takes to grow or shrink when a row or card comes or goes, in seconds.
    static let cardAnimation = 0.2
    /// A selected text's card, which the rows under it make room for: it fades in once they have moved out of its
    /// way and fades out before they move back over it, so the mode row never slides across its text.
    static let cardRowTransition: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)).animation(.smooth(duration: 0.2).delay(0.1)),
        removal: .opacity.animation(.easeOut(duration: 0.06))
    )

    @Bindable var session: ChatSession
    let preferences: Preferences
    let whatsNew: WhatsNew
    let updater: Updater
    let updateNotice: UpdateNotice
    let shortcutSetup: ShortcutSetup
    let layout: PanelLayout
    /// Fits the window: its height, and how much of it is room above the card for a panel of actions that
    /// opens upward, which raises the window's top so the card itself stays where it is on the screen.
    let onHeightChange: (_ height: CGFloat, _ roomAbove: CGFloat) -> Void
    let onClose: () -> Void
    /// Opens Settings, on a pane when one is given.
    let openSettings: (SettingsPane?) -> Void
    /// Makes the window key after a drop. Finder keeps the keyboard through a drag, which leaves the panel's
    /// controls drawn inactive and the input deaf to typing.
    var takeKeyboard: () -> Void = {}
    /// The screen the window is on, for the screenshot button above the card.
    var screen: () -> NSScreen? = { NSScreen.main }
    /// Fits the input's editing back into the input once its placeholder changed (see `refitFieldBeingEdited()`).
    var refitInput: () -> Void = {}
    /// Where what the buttons above the card added came from.
    var sources = ContextSources()
    /// Insert Answer, for the chat's actions.
    var inserter: AnswerInserter?

    @FocusState private var isInputFocused: Bool
    @State private var conversationHeight: CGFloat = 0
    @State private var isDropTargeted = false
    /// How tall the card is with its margins, where an open panel of actions reaches, and the room the window
    /// makes above the card for a panel that opens upward past the card's top.
    @State private var cardHeight: CGFloat = 0
    @State private var actionPanelSpan: ActionPanelSpan?
    @State private var roomAbove: CGFloat = 0
    /// A moment of today, for the capsules that say what today has cost: moved on when the day changes, and when
    /// the window opens on a new one.
    @State private var today = Date.now

    /// A game has its footer from the start; its transcript waits for the first move.
    private var hasConversation: Bool { !session.turns.isEmpty || session.isPlaying }
    /// The follow-ups under the last answer, or the capsule that says they are coming, show while the input is empty:
    /// typing or asking puts them away.
    private var showsFollowUps: Bool {
        (!session.followUps.isEmpty || session.isSuggestingFollowUps) && !session.isStreaming && !session.isPlaying
            && session.draft.trimmed.isEmpty
    }
    private var context: PanelContext {
        PanelContext(session: session, preferences: preferences, layout: layout, openSettings: openSettings, insertion: inserter?.insertion, copyDiagnostics: copyDiagnostics)
    }
    /// Who is asking when an agent stops to ask, for the prompt card.
    private var agentName: String { preferences.activeProvider?.name ?? "The agent" }
    /// The update the capsule under the card offers, unless its cross hid that version.
    private var offeredUpdate: Updater.State? { updateNotice.offer(for: updater.state) }
    /// Whether the capsules under the card show, for the window to make room for them.
    private var hasAnnouncements: Bool { whatsNew.update != nil || offeredUpdate != nil || crashNotice.isOffered }
    /// The diagnostics the capsule under the card offers once after a crash, and says Copied when they were.
    private let crashNotice = CrashNotice.shared
    /// A mode's presets above the card, those with text to put in the input.
    private func presets(for kind: ProviderKind) -> [PromptPreset] {
        preferences[presets: kind].filter { !$0.text.trimmed.isEmpty }
    }
    /// The text written in the window for a decision, for its card.
    private var typedState: Binding<String> {
        Binding(get: { session.typedState ?? "" }, set: { session.typedState = $0 })
    }
    /// What LLMs and agents have cost today, on an empty panel.
    private var costNudges: [CostNudge] {
        guard !hasConversation else { return [] }
        return CostNudge.nudges { session.usage.cost(of: $0, onDayOf: today) }
    }

    var body: some View {
        let costNudges = costNudges
        GlassEffectContainer {
            VStack(spacing: 0) {
                inputRow
                if !session.draftSelections.isEmpty, !session.isPlaying {
                    VStack(spacing: 8) {
                        ForEach(session.draftSelections) { selection in
                            SelectionCard(selection: selection) {
                                session.removeSelection(selection.id)
                                isInputFocused = true
                            }
                            .transition(Self.cardRowTransition)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(Self.cardRowTransition)
                }
                // A decision's context: the row that asks for it, which Write It swaps for the card to write it in,
                // in the same place. Not while the mode has nothing ready, when the setup row below says what to do.
                if session.needsDecisionState, preferences.activeProvider != nil {
                    DecisionStateRow { session.writeState() }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .transition(Self.cardRowTransition)
                }
                if session.typedState != nil, !session.isPlaying {
                    TypedStateCard(text: typedState) {
                        session.removeTypedState()
                        isInputFocused = true
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(Self.cardRowTransition)
                }
                ModeBar(preferences: preferences, session: session, layout: layout) { isInputFocused = true }
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                if shortcutSetup.showsNotice && !hasConversation {
                    ShortcutNotice(change: shortcutSetup.changeShortcut, dismiss: shortcutSetup.dismissNotice)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if !session.draftImages.isEmpty || !session.draftFiles.isEmpty {
                    AttachmentStrip(images: session.draftImages, files: session.draftFiles, size: 48, onRemove: session.removeAttachment)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if whatsNew.isExpanded, let update = whatsNew.update {
                    WhatsNewCard(update: update, dismiss: whatsNew.dismiss)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if !session.turns.isEmpty {
                    Divider().padding(.horizontal, 18)
                    conversation
                }
                if let failure = session.failure {
                    FailureRow(message: failure, showsSettings: session.failureNeedsSettings) { openSettings(nil) }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else if let notice = session.fileNotice {
                    SwitchModeRow(message: notice, symbol: "doc", button: "Switch to Agent") {
                        preferences.mode = .agent
                        isInputFocused = true
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                } else if let notice = session.pictureNotice {
                    SwitchModeRow(message: notice, symbol: "photo", button: "Switch to LLM") {
                        preferences.mode = .llm
                        isInputFocused = true
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                } else if let notice = session.bulkNotice {
                    SwitchModeRow(message: notice, symbol: DecisionScope.whole.symbol, button: "Whole Text") {
                        preferences.decisionScope = .whole
                        isInputFocused = true
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                } else if !hasConversation && preferences.activeProvider == nil {
                    SetupRow(kind: preferences.mode) { openSettings(.provider(preferences.mode.providers[0])) }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else if let rematch = session.rematch, !rematch.isAfterGame {
                    rematchTray(rematch)
                } else if let nudge = nudgeMessage {
                    NudgeRow(message: nudge, symbol: session.game?.symbol ?? "sparkle", button: openingButton)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else if showsSelectionHint {
                    SelectionHintRow {
                        onClose()
                        SelectionAccess.shared.request()
                    } dismiss: {
                        SelectionAccess.shared.isHintDismissed = true
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
                if let rematch = session.rematch, rematch.isAfterGame {
                    rematchTray(rematch)
                }
                if hasConversation {
                    footer
                }
            }
            .frame(width: PanelController.width)
            // Empty space in the card moves the window.
            .background { WindowDragArea() }
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(.primary.opacity(0.35), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        }
        .padding(PanelController.margin)
        .padding(.top, ContextButtons.roomAbove)
        .padding(.bottom, hasAnnouncements || session.expiresAt != nil || !costNudges.isEmpty ? Announcements.roomBelow : 0)
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                // Lined up with the sparkle under them.
                ContextButtons(session: session, preferences: preferences, sources: sources, screen: screen, close: onClose) { isInputFocused = true }
                    .fixedSize()
                // Lined up with the gear under them, in the room the buttons leave: each mode's presets in a row of
                // its own, the current mode's up and the others sunk, so a change of mode sinks one row as the
                // next rises. Every row stays in the view tree, faded and disabled.
                ZStack(alignment: .trailing) {
                    ForEach(ProviderKind.allCases) { kind in
                        let presets = presets(for: kind)
                        PromptPresets(presets: presets, draft: session.draft, isShown: !hasConversation && preferences.mode == kind) { preset, sends in
                            session.apply(preset, among: presets, sending: sends)
                            if !sends { isInputFocused = true }
                        }
                    }
                }
            }
            .padding(.leading, PanelController.margin + 18)
            .padding(.trailing, PanelController.margin + 12)
            .padding(.top, ContextButtons.inset)
        }
        .overlay(alignment: .bottomLeading) {
            // Lined up with the buttons above the card.
            Announcements(whatsNew: whatsNew, update: offeredUpdate, openUpdate: openUpdate, hideUpdate: updateNotice.hide, crash: crashNotice, copyDiagnostics: copyDiagnostics)
                .padding(.leading, PanelController.margin + 18)
                .padding(.bottom, Announcements.inset)
        }
        .overlay(alignment: .bottomTrailing) {
            // Lined up with the footer's actions.
            if let expiresAt = session.expiresAt {
                ChatTimer(expiresAt: expiresAt) { session.addTime(minutes: $0) }
                    .padding(.trailing, PanelController.margin + 12)
                    .padding(.bottom, Announcements.inset)
                    .transition(.opacity)
            }
            // In the timer's place before there is a chat.
            if !costNudges.isEmpty {
                CostNudges(nudges: costNudges)
                    .padding(.trailing, PanelController.margin + 12)
                    .padding(.bottom, Announcements.inset)
                    .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) {
            cardHeight = $0
            fitWindow()
        }
        .padding(.top, roomAbove)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlayPreferenceValue(ActionPanelAnchors.self) { anchors in
            ActionPanelHost(anchors: anchors, context: context, roomAbove: roomAbove) { span in
                actionPanelSpan = span
                // The span was laid out with the current room above; what the card alone would leave is the
                // same whatever the room, so this settles at once.
                roomAbove = span.map { max(0, ActionPanelHost.inset - ($0.top - roomAbove)) } ?? 0
                fitWindow()
            }
        }
        .onDrop(of: [.fileURL, .image, .plainText], isTargeted: $isDropTargeted, perform: acceptDrop)
        .onChange(of: layout.focusRequest) {
            isInputFocused = true
            if !Calendar.current.isDate(today, inSameDayAs: .now) { today = .now }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in today = .now }
        .onChange(of: session.isStreaming) {
            if !session.isStreaming && layout.actionPanel == nil { isInputFocused = true }
        }
        .onChange(of: hasConversation) {
            if !hasConversation, layout.actionPanel?.kind == .chat { layout.actionPanel = nil }
        }
        .animation(.smooth(duration: Self.cardAnimation), value: session.draftImages)
        .animation(.smooth(duration: Self.cardAnimation), value: session.draftFiles)
        .animation(.smooth(duration: Self.cardAnimation), value: session.draftSelections)
        .animation(.smooth(duration: Self.cardAnimation), value: session.fileNotice)
        .animation(.smooth(duration: Self.cardAnimation), value: session.pictureNotice)
        .animation(.smooth(duration: Self.cardAnimation), value: session.bulkNotice)
        .animation(.smooth(duration: Self.cardAnimation), value: session.needsDecisionState)
        .animation(.smooth(duration: Self.cardAnimation), value: session.typedState == nil)
        .animation(.smooth(duration: Self.cardAnimation), value: session.failure)
        .animation(.smooth(duration: Self.cardAnimation), value: session.nudge)
        .animation(.smooth(duration: Self.cardAnimation), value: session.rematch)
        .animation(.smooth(duration: Self.cardAnimation), value: showsFollowUps)
        .animation(.smooth(duration: Self.cardAnimation), value: session.followUps)
        .animation(.smooth(duration: Self.cardAnimation), value: whatsNew.isExpanded)
        .animation(.smooth(duration: Self.cardAnimation), value: whatsNew.update)
        .animation(.smooth(duration: Self.cardAnimation), value: offeredUpdate)
        .animation(.smooth(duration: Self.cardAnimation), value: crashNotice.isOffered)
        .animation(.smooth(duration: Self.cardAnimation), value: session.expiresAt == nil)
        .animation(.smooth(duration: Self.cardAnimation), value: costNudges.isEmpty)
        .animation(.smooth(duration: Self.cardAnimation), value: shortcutSetup.showsNotice)
    }

    /// Fits the window to the card, taller above it while a panel of actions opens upward past its top, and
    /// lower while one reaches below it, with room for the panel's shadow.
    private func fitWindow() {
        let panelBottom = actionPanelSpan.map { $0.bottom + 28 } ?? 0
        onHeightChange(max(roomAbove + cardHeight, panelBottom), roomAbove)
    }

    /// A staged update restarts into it; a found one opens Sparkle's window, which the panel would cover.
    private func openUpdate() {
        if updater.stagedUpdate != nil {
            updater.installStagedUpdate()
        } else {
            onClose()
            updater.checkForUpdates()
        }
    }

    /// Copies the diagnostics, from the crash capsule or the sparkle's panel, and has the capsule say Copied.
    private func copyDiagnostics() {
        Task { await crashNotice.copyDiagnostics(of: session, preferences: preferences, updates: updater.status) }
    }

    /// The card under the input: a game's nudge, or its invitation while a round waits to be opened.
    private var nudgeMessage: String? {
        session.nudge ?? (session.gameState?.isOpening == true ? session.game?.rules.invitation : nil)
    }

    /// The other side's opening of a round that waits for one, on the invitation card: Random Rhyme, Random
    /// Word, Random Category. The same as Return with nothing typed.
    private var openingButton: NudgeRow.Button? {
        guard !session.isStreaming, let opening = session.gameState?.opening else { return nil }
        return NudgeRow.Button(title: opening.button) {
            session.choose(opening.button)
            isInputFocused = true
        }
    }

    private func rematchTray(_ rematch: RematchOffer) -> some View {
        RematchTray(offer: rematch) {
            session.playAgain()
            isInputFocused = true
        } putAway: {
            session.putAwayRematch()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .transition(.opacity)
    }

    /// Until Meraline may read the selection, an empty panel says what the shortcut could bring.
    private var showsSelectionHint: Bool {
        let access = SelectionAccess.shared
        return preferences.bringsSelection && !access.isGranted && !access.isHintDismissed
            && !hasConversation && !session.isPlaying && session.draftSelections.isEmpty
    }

    private var placeholder: String {
        guard let state = session.gameState else {
            if session.isDeciding {
                let ask = hasConversation ? "Ask for another decision" : "Ask something Jev can decide"
                return session.isAnonymous ? "\(ask) secretly…" : "\(ask)…"
            }
            let texts = session.draftSelections
            let ask = texts.count > 1 ? "Ask about them"
                : texts.first.map { $0.isFromClipboard ? "Ask about the clipboard" : "Ask about the selection" }
                ?? (hasConversation ? "Ask a follow-up" : "Ask anything")
            return session.isAnonymous ? "\(ask) secretly…" : "\(ask)…"
        }
        switch state.phase {
        case .yourMove(let placeholder, _, _): return placeholder
        case .waiting: return "The model is thinking…"
        case .modelMoves: return "Press Return for the model’s move…"
        case .opening(let opening), .over(_, let opening): return opening.placeholder
        }
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: 12) {
            SparkleButton(session: session, isOpen: layout.actionPanel?.kind == .providers) {
                layout.toggleActionPanel(.providers)
            }

            TextField(placeholder, text: $session.draft.onOneLine)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($isInputFocused)
                .tint(.meralinePink)
                .onSubmit(session.send)
                .disabled(session.isStreaming)
                .onChange(of: placeholder) { refitInput() }

            PinButton(preferences: preferences)

            Button { openSettings(nil) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            .hoverTip("Settings (⌘,)", edge: .bottom)
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(minHeight: 60)
    }

    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let game = session.game {
                    GameTranscript(
                        lines: game.rules.lines(for: session.turns),
                        choices: session.isStreaming ? [] : session.gameState?.choices ?? [],
                        activity: session.isStreaming ? .some(session.turns.last?.activity) : nil,
                        prompt: session.isStreaming ? session.turns.last?.pendingPrompt : nil,
                        agent: agentName,
                        answer: { session.answer($0, with: $1) },
                        explain: explain
                    ) { choice in
                        session.choose(choice)
                        isInputFocused = true
                    }
                } else {
                    ForEach(session.turns) { turn in
                        TurnView(
                            turn: turn,
                            isAnswering: session.isStreaming && turn.id == session.turns.last?.id,
                            showsChanges: layout.answersShowingChanges.contains(turn.id),
                            toggleChanges: { layout.toggleChanges(of: turn.id) },
                            isLastAnswer: turn.id == session.turns.last(where: { !$0.answer.isEmpty })?.id,
                            unsureBelow: preferences.unsureBelow,
                            agent: agentName,
                            answer: { session.answer($0, with: $1) },
                            explain: explain,
                            explainTool: explainTool(for: turn)
                        )
                    }
                    .environment(\.answerWorkspace, session.workspace?.url)
                    if showsFollowUps {
                        FollowUpChips(questions: session.followUps) { question, sends in
                            session.followUp(question, sending: sends)
                            if !sends { isInputFocused = true }
                        }
                        .padding(.top, -6)
                        .transition(FollowUpChips.transition)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { conversationHeight = $0 }
            .environment(\.answerZoom, layout.answerZoom.scale)
        }
        .frame(height: min(conversationHeight, layout.maximumConversationHeight))
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    /// The Why? button on an agent's ask: the agent says in one line why it wants the tool (see `ToolReason`).
    private func explain(_ prompt: AgentPrompt) async throws -> String {
        try await ToolReason.explain(prompt, in: session.turns, settings: preferences[.claudeCode], instructions: preferences.instructions(for: .toolReason))
    }

    /// A click on a tool under a finished answer: the provider that answered says in one line why it used the tool
    /// (see `ToolReason`). None once that provider isn't ready, since the chat would go somewhere new.
    private func explainTool(for turn: ChatSession.Turn) -> ((Int) async throws -> String)? {
        guard let provider = turn.provider, preferences[provider].isReady(for: provider) else { return nil }
        return { index in
            try await ToolReason.explain(
                toolAt: index, of: turn, in: session.turns, provider: provider,
                settings: preferences[provider], instructions: preferences.instructions(for: .toolReason)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let game = session.game, let state = session.gameState {
                Label(state.status, systemImage: game.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let provider = preferences.activeProvider {
                Label(preferences[provider].model.isEmpty ? provider.name : preferences[provider].model, systemImage: provider.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if session.isStreaming {
                ProgressView()
                    .controlSize(.mini)
                    .hoverTip("Answering")
            }
            if !layout.answerZoom.isActualSize, context.canZoomAnswers {
                AnswerZoomBadge(zoom: layout.answerZoom) { layout.zoomAnswers(.actualSize) }
                    .transition(.opacity)
            }
            let menu = context.chatMenu
            ActionBar(primary: menu?.primary, isOpen: layout.actionPanel?.kind == .chat, copyNotice: layout.copyNotice) {
                if let primary = menu?.primary { context.run(primary, in: .chat) }
            } openActions: {
                layout.toggleActionPanel(.chat)
            }
            .actionPanelAnchor(.chat)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .animation(.smooth(duration: 0.2), value: layout.answerZoom.isActualSize)
    }

    /// Files and pictures attach, and text dragged out of another app waits in a card of its own, as a
    /// selection does, named after that app. A game takes no text.
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        defer { takeKeyboard() }
        var accepted = false
        for provider in providers {
            switch ClipboardContent.drop(of: provider.registeredTypeIdentifiers) {
            case .file:
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in session.attach(fileAt: url) }
                }
            case .image:
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        if let image = NSImage(data: data) { session.attach(image) }
                    }
                }
            case .text where !session.isPlaying:
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in
                        guard let selection = SelectedText.handedOver(text) else { return }
                        Log.panel.info("Text dropped, \(selection.text.count) characters")
                        session.bring(selection)
                    }
                }
            case .text, nil:
                continue
            }
        }
        return accepted
    }
}

/// The sparkle at the start of the input row. A click opens its panel of actions: the ready providers of the
/// current mode, the other mode, anonymous mode, and Settings (see `PanelContext.providersMenu`). The toggle
/// under the input switches modes too, and the games and the recent chats have their own buttons beside it.
private struct SparkleButton: View {
    let session: ChatSession
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            SparkleIcon(isStreaming: session.isStreaming, isAnonymous: session.isAnonymous)
                .frame(width: 28, height: 28)
                .background {
                    if isOpen { Circle().fill(.primary.opacity(0.08)).padding(-3) }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .actionPanelAnchor(.providers)
        .hoverTip(session.isAnonymous
            ? "Anonymous mode is on: this chat won’t go to Recent Chats (⇧⌘N to turn it off)"
            : "Providers, modes, and settings", edge: .bottom)
        .accessibilityLabel("Provider")
        .accessibilityValue(session.isAnonymous ? "Anonymous mode on" : "")
    }
}

private struct TurnView: View {
    let turn: ChatSession.Turn
    let isAnswering: Bool
    /// Whether the answer shows what it changed in the text its question was about, in its place.
    let showsChanges: Bool
    let toggleChanges: () -> Void
    /// Whether this is the last answer, whose changes ⌘D shows.
    var isLastAnswer = false
    /// Under this confidence a decision shows as Not Sure.
    var unsureBelow = Decision.defaultUnsureBelow
    let agent: String
    let answer: (AgentPrompt.ID, AgentAnswer) -> Void
    var explain: ((AgentPrompt) async throws -> String)?
    /// Asks the provider that answered why it used one of the answer's tools.
    var explainTool: ((Int) async throws -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(turn.selections) { selection in
                SelectionQuote(selection: selection)
            }
            if !turn.question.isEmpty {
                Text(turn.question)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !turn.images.isEmpty || !turn.files.isEmpty {
                AttachmentStrip(images: turn.images, files: turn.files, size: 40)
            }
            if let notice = turn.notice {
                Label {
                    Text(notice)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            if let batch = turn.decisions {
                BulkDecisionCard(batch: batch, unsureBelow: unsureBelow, isAnswering: isAnswering)
            } else if let decision = turn.decision {
                DecisionCard(decision: decision, unsureBelow: unsureBelow)
            } else if !turn.answer.isEmpty {
                if showsChanges, let changes = turn.changes {
                    ChangesView(changes: changes)
                } else {
                    MarkdownView(markdown: turn.answer)
                }
            }
            if let changes = turn.changes {
                ChangesToggle(changes: changes, isShowingChanges: showsChanges, hasShortcut: isLastAnswer, toggle: toggleChanges)
            }
            if !turn.presentedFiles.isEmpty {
                VStack(spacing: 8) {
                    ForEach(turn.presentedFiles) { PresentedFileCard(file: $0) }
                }
            }
            if let prompt = turn.pendingPrompt {
                PromptCard(prompt: prompt, agent: agent, answer: { answer(prompt.id, $0) }, explain: explain)
                    .id(prompt.id)
            } else if isAnswering && (turn.answer.isEmpty || turn.activity != nil) {
                ActivityRow(activity: turn.activity)
            }
            let settled = turn.prompts.filter { !$0.isPending }
            if !settled.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(settled) { PromptOutcomeRow(prompt: $0, agent: agent) }
                }
            }
            if !turn.tools.isEmpty && !turn.answer.isEmpty {
                ToolTrail(tools: turn.tools, agent: turn.provider?.name ?? agent, explain: isAnswering ? nil : explainTool)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An agent's ask, with the means to settle it: Allow and Deny for a tool, with Why? for the agent's reason
/// in one line, or a question's choices as buttons and a field for an answer of your own. One question with
/// single choices is answered by the first tap; several, or several choices, wait for Done. Neutral glass,
/// with the panel's faint pink on the default choice.
private struct PromptCard: View {
    let prompt: AgentPrompt
    let agent: String
    let answer: (AgentAnswer) -> Void
    /// Asks the agent why it wants the tool. Without it there is no Why? button.
    var explain: ((AgentPrompt) async throws -> String)?
    /// The labels picked so far, by question.
    @State private var picks: [String: [String]] = [:]
    /// Answers typed instead of picked, by question.
    @State private var typed: [String: String] = [:]
    /// Nil until Why? is clicked. Kept by the card alone, so the reason goes when the ask is settled.
    @State private var why: WhyAnswer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch prompt.kind {
            case .permission(let activity, let detail):
                permission(activity, detail: detail)
            case .question(let questions):
                ForEach(questions) { question in
                    self.question(question, of: questions)
                }
                if questions.count > 1 || questions.contains(where: \.multiSelect) {
                    HStack {
                        Spacer()
                        Button("Done") { send(questions) }
                            .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                            .keyboardShortcut(.defaultAction)
                            .disabled(!isComplete(questions))
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func permission(_ activity: Activity, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: activity.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agent) asks to \(activity.request)")
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 8)
                if explain != nil, why == nil || why?.isFailed == true {
                    Button("Why?") { why = .asking }
                        .buttonStyle(.glass)
                        .hoverTip("Ask \(agent) why it wants this")
                }
                Button("Deny") { answer(.deny) }
                    .buttonStyle(.glass)
                Button("Allow") { answer(.allow) }
                    .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                    .keyboardShortcut(.defaultAction)
            }
            if let why {
                WhyLine(why: why, agent: agent)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
            }
        }
        .task(id: why == .asking) {
            guard why == .asking, let explain else { return }
            do {
                why = .reason(try await explain(prompt))
                Log.chat.info("Agent's reason for its ask shown")
            } catch {
                // Settling the ask takes the card away and stops the run; that is no failure.
                guard !Task.isCancelled else { return }
                Log.chat.error("Couldn’t get the agent's reason: \(error.localizedDescription)")
                why = .failed(error.localizedDescription)
            }
        }
    }

    private func question(_ question: AgentPrompt.Question, of questions: [AgentPrompt.Question]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !question.header.isEmpty {
                Text(question.header)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(question.text)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !question.options.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(question.options) { option in
                        let picked = picks[question.id, default: []].contains(option.label)
                        Button(option.label) { pick(option.label, for: question, of: questions) }
                            .buttonStyle(.glass(picked ? .regular.tint(.meralinePink.opacity(0.18)) : .regular))
                            .hoverTip(option.detail ?? option.label)
                    }
                }
            }
            TextField("Something else…", text: typedBinding(question).onOneLine)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .tint(.meralinePink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                .onSubmit { if isComplete(questions) { send(questions) } }
        }
    }

    private func typedBinding(_ question: AgentPrompt.Question) -> Binding<String> {
        Binding(get: { typed[question.id] ?? "" }, set: { typed[question.id] = $0 })
    }

    private func pick(_ label: String, for question: AgentPrompt.Question, of questions: [AgentPrompt.Question]) {
        if question.multiSelect {
            var labels = picks[question.id, default: []]
            if let index = labels.firstIndex(of: label) { labels.remove(at: index) } else { labels.append(label) }
            picks[question.id] = labels
        } else {
            picks[question.id] = [label]
            if questions.count == 1 { send(questions) }
        }
    }

    /// The typed answer when there is one, otherwise the picks in the order they were made.
    private func answerText(for question: AgentPrompt.Question) -> String {
        let text = (typed[question.id] ?? "").trimmed
        return text.isEmpty ? picks[question.id, default: []].joined(separator: ", ") : text
    }

    private func isComplete(_ questions: [AgentPrompt.Question]) -> Bool {
        questions.allSatisfy { !answerText(for: $0).isEmpty }
    }

    private func send(_ questions: [AgentPrompt.Question]) {
        answer(.answers(Dictionary(uniqueKeysWithValues: questions.map { ($0.text, answerText(for: $0)) })))
    }
}

/// How an ask was settled, in one quiet line under the answer.
private struct PromptOutcomeRow: View {
    let prompt: AgentPrompt
    let agent: String

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .hoverTip(text)
    }

    private var text: String {
        switch (prompt.kind, prompt.resolution) {
        case (.permission(let activity, let detail), .allowed?):
            "You let \(agent) \(activity.request)\(Self.suffix(detail))"
        case (.permission(let activity, let detail), .denied?):
            "You didn’t let \(agent) \(activity.request)\(Self.suffix(detail))"
        case (.permission(let activity, let detail), .declinedByAgent?):
            "\(agent) wanted to \(activity.request)\(Self.suffix(detail)) but turned itself down: its run mode can’t ask"
        case (.question(let questions), .answered(let answers)?):
            "You answered: \(questions.compactMap { answers[$0.text] }.joined(separator: ", "))"
        case (.question, .denied?):
            "You didn’t answer \(agent)’s question"
        default:
            ""
        }
    }

    private var symbol: String {
        switch prompt.resolution {
        case .allowed?: "checkmark.circle"
        case .denied?: "xmark.circle"
        case .answered?: "text.bubble"
        case .declinedByAgent?: "hand.raised"
        case nil: "questionmark.circle"
        }
    }

    private static func suffix(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "" }
        return " (\(detail))"
    }
}

/// Lays children out left to right and wraps to the next line when the row is full. Each child is
/// offered at most `maximumItemWidth`, so a long label truncates instead of taking a whole row.
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var maximumItemWidth: CGFloat?

    private func itemProposal(in width: CGFloat) -> ProposedViewSize {
        ProposedViewSize(width: min(maximumItemWidth ?? width, width), height: nil)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let item = itemProposal(in: width)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(item)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let item = itemProposal(in: bounds.width)
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(item)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: item)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A game's transcript: its lines, the model's move while it thinks, and buttons for the choices on your
/// move. The buttons play themselves.
private struct GameTranscript: View {
    let lines: [GameLine]
    let choices: [String]
    /// Set while the model is moving: what it is doing, if the provider says.
    let activity: Activity??
    /// An agent's ask while it moves, if it stopped to ask.
    let prompt: AgentPrompt?
    let agent: String
    let answer: (AgentPrompt.ID, AgentAnswer) -> Void
    var explain: ((AgentPrompt) async throws -> String)?
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { GameLineView(line: $0) }
            if let prompt {
                PromptCard(prompt: prompt, agent: agent, answer: { answer(prompt.id, $0) }, explain: explain)
                    .id(prompt.id)
            } else if let activity {
                ActivityRow(activity: activity)
            }
            if !choices.isEmpty {
                HStack(spacing: 8) {
                    ForEach(choices, id: \.self) { choice in
                        Button(choice) { choose(choice) }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Your words in semibold gray and the model's in the primary color, so a line reads as a conversation.
private struct GameLineView: View {
    let line: GameLine

    var body: some View {
        switch line.kind {
        case .heading:
            Text(line.text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, line.id == 0 ? 0 : 6)
        case .verse:
            Text(Self.verse(line.pieces))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .tiles(let shuffles):
            LetterTiles(letters: line.pieces.filter { $0.voice != .plain }.map(\.text), shuffles: shuffles)
                .padding(.vertical, 2)
        case .verdict(let youWon):
            Label {
                Text(line.text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: youWon == true ? "checkmark.circle" : youWon == false ? "xmark.circle" : "flag.checkered")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        case .note:
            Text(line.text)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
    }

    static func verse(_ pieces: [GameLine.Piece]) -> AttributedString {
        var verse = AttributedString()
        for piece in pieces {
            var run = AttributedString(piece.text)
            switch piece.voice {
            case .you:
                run.font = .system(size: 15, weight: .semibold)
                run.foregroundColor = .secondary
            case .model:
                run.font = .system(size: 15)
                run.foregroundColor = .primary
            case .plain:
                run.font = .system(size: 15)
                run.foregroundColor = Color(nsColor: .tertiaryLabelColor)
            }
            if piece.isMarked {
                run.font = .system(size: 15, weight: .bold)
                run.underlineStyle = .single
            }
            verse += run
        }
        return verse
    }
}

/// A line from a game: its invitation, why a move came back, or that the round is over. Nothing went
/// wrong, so it is plain glass rather than the orange of `FailureRow`.
private struct NudgeRow: View {
    /// A button at the card's right, such as a game's Random Word.
    struct Button {
        let title: String
        let action: () -> Void
    }

    let message: String
    let symbol: String
    var button: Button?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let button {
                SwiftUI.Button(button.title, action: button.action)
                    .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                    .hoverTip("\(button.title), or press Return with nothing typed")
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Why the draft waits, with the switch that would send it: files while asking an LLM or for a decision,
/// pictures while asking for a decision, or more words or lines than a decision about each takes.
private struct SwitchModeRow: View {
    let message: String
    let symbol: String
    let button: String
    let switchMode: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(button, action: switchMode)
                .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct ActivityRow: View {
    let activity: Activity?

    var body: some View {
        HStack(spacing: 8) {
            if let activity {
                Image(systemName: activity.symbol)
                    .symbolEffect(.pulse, options: .repeating)
                    .frame(width: 18)
            } else {
                Image(systemName: "ellipsis")
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                    .frame(width: 18)
            }
            if let activity, activity != .thinking {
                Text(activity.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
            } else {
                ThinkingStatusText()
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .animation(.smooth(duration: 0.2), value: activity)
    }
}

/// Murmurs a different line from `ThinkingStatus` every few seconds until the first word of the answer
/// arrives. Waiting for the first byte and an explicit thinking phase share one view, so the line keeps
/// rotating instead of restarting when a model moves from one to the other.
private struct ThinkingStatusText: View {
    @State private var line = ThinkingStatus.line()

    var body: some View {
        Text(line)
            .lineLimit(1)
            .id(line)
            .transition(.blurReplace)
            .accessibilityLabel("Thinking")
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: ThinkingStatus.rotationInterval)
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.45)) { line = ThinkingStatus.line(after: line) }
                }
            }
    }
}

/// A question's images and files, in a row that scrolls sideways when it runs long. In the draft, each has
/// a cross to take it out again.
private struct AttachmentStrip: View {
    let images: [ImageAttachment]
    let files: [FileAttachment]
    let size: CGFloat
    var onRemove: ((UUID) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: onRemove == nil ? 6 : 8) {
                ForEach(images) { image in
                    AttachmentThumbnail(image: image, size: size)
                        .overlay(alignment: .topTrailing) { removeButton(for: image.id, label: "Remove image") }
                }
                ForEach(files) { file in
                    FileChip(file: file, height: size)
                        .overlay(alignment: .topTrailing) { removeButton(for: file.id, label: "Remove \(file.name)") }
                }
            }
            // Room for the crosses, which stand out over the top right corners.
            .padding(.top, onRemove == nil ? 0 : 6)
            .padding(.trailing, onRemove == nil ? 0 : 6)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.leading)
        .padding(.top, onRemove == nil ? 0 : -6)
    }

    @ViewBuilder
    private func removeButton(for id: UUID, label: String) -> some View {
        if let onRemove {
            Button { onRemove(id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 18, height: 18)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .offset(x: 6, y: -6)
        }
    }
}

/// A file for an agent: its Finder icon and its name, shortened in the middle when long.
private struct FileChip: View {
    let file: FileAttachment
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: height * 0.6, height: height * 0.6)
            Text(Self.shortened(file.name))
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: height)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .hoverTip(file.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Attached file \(file.name)")
    }

    /// The row scrolls, so it offers a chip all the width it wants; a long name is cut here instead, keeping
    /// its extension.
    static func shortened(_ name: String) -> String {
        guard name.count > 28 else { return name }
        return "\(name.prefix(16))…\(name.suffix(11))"
    }
}

private struct AttachmentThumbnail: View {
    let image: ImageAttachment
    let size: CGFloat

    var body: some View {
        Group {
            if let nsImage = NSImage(data: image.data) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .accessibilityLabel("Attached image")
    }
}

private struct FailureRow: View {
    let message: String
    let showsSettings: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsSettings {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 16))
    }
}

/// What to do when the current mode has nothing ready: connect an LLM, turn on an agent, or add a decision
/// model's key.
private struct SetupRow: View {
    let kind: ProviderKind
    let openSettings: () -> Void

    private var title: String {
        switch kind {
        case .llm: "Connect an AI provider"
        case .agent: "Turn on an agent"
        case .decision: "Connect a decision model"
        }
    }

    private var detail: String {
        switch kind {
        case .llm: "Add an API key or turn on a local model to start asking."
        case .agent: "Install Claude Code, Codex, or OpenCode, then turn it on in Settings."
        case .decision: "Add your TypeSafe API key in Settings, and Jev answers yes or no about the text you add."
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            (kind == .agent ? kind.image : Image(systemName: "key.fill"))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

enum MarkdownText {
    static func render(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var rendered = try? AttributedString(markdown: markdown, options: options) else {
            return AttributedString(markdown)
        }
        for run in rendered.runs where run.link != nil {
            rendered[run.range].foregroundColor = .primary
            rendered[run.range].underlineStyle = .single
        }
        return rendered
    }
}
