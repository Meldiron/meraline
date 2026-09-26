import SwiftUI
import UniformTypeIdentifiers

struct ChatPanelView: View {
    @Bindable var session: ChatSession
    let preferences: Preferences
    let layout: PanelLayout
    let onHeightChange: (CGFloat) -> Void
    let onClose: () -> Void
    /// Opens Settings, on a pane when one is given.
    let openSettings: (SettingsPane?) -> Void

    @FocusState private var isInputFocused: Bool
    @State private var conversationHeight: CGFloat = 0
    @State private var isDropTargeted = false

    private var hasConversation: Bool { !session.turns.isEmpty }
    /// Who is asking when an agent stops to ask, for the prompt card.
    private var agentName: String { preferences.activeProvider?.name ?? "The agent" }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                inputRow
                ModeBar(preferences: preferences, session: session) { isInputFocused = true }
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                if !session.draftImages.isEmpty {
                    DraftImageTray(images: session.draftImages, onRemove: session.removeImage)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if hasConversation {
                    Divider().padding(.horizontal, 18)
                    conversation
                }
                if let failure = session.failure {
                    FailureRow(message: failure, showsSettings: session.failureNeedsSettings) { openSettings(nil) }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else if !hasConversation && preferences.activeProvider == nil {
                    SetupRow(kind: preferences.mode) { openSettings(.provider(preferences.mode.providers[0])) }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else if let nudge = session.nudge {
                    NudgeRow(message: nudge, symbol: session.game?.symbol ?? "sparkle")
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
                if hasConversation {
                    footer
                }
            }
            .frame(width: PanelController.width)
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
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: acceptDrop)
        .onChange(of: layout.focusRequest) { isInputFocused = true }
        .onChange(of: session.isStreaming) { if !session.isStreaming { isInputFocused = true } }
        .animation(.smooth(duration: 0.2), value: session.draftImages)
        .animation(.smooth(duration: 0.2), value: session.failure)
        .animation(.smooth(duration: 0.2), value: session.nudge)
    }

    private var placeholder: String {
        guard let state = session.gameState else {
            return hasConversation ? "Ask a follow-up…" : "Ask anything…"
        }
        switch state.phase {
        case .yourMove(let placeholder, _, _): return placeholder
        case .waiting: return "The model is thinking…"
        case .modelMoves: return "Press Return for the model’s move…"
        case .over(_, let rematch): return rematch.placeholder
        }
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderMenu(preferences: preferences, session: session, openSettings: openSettings) { isInputFocused = true }

            TextField(placeholder, text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .lineLimit(1...8)
                .focused($isInputFocused)
                .tint(.meralinePink)
                .onSubmit(session.send)
                .disabled(session.isStreaming)

            Button { preferences.isPinned.toggle() } label: {
                Image(systemName: preferences.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(preferences.isPinned ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                    .rotationEffect(.degrees(45))
                    .frame(width: 32, height: 32)
                    .glassEffect(
                        preferences.isPinned ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(),
                        in: .circle
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("p")
            .help(preferences.isPinned ? "Unpin: close when clicking elsewhere (⌘P)" : "Pin: stay open when clicking elsewhere (⌘P)")
            .accessibilityLabel(preferences.isPinned ? "Unpin" : "Pin")

            Button { openSettings(nil) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            .help("Settings (⌘,)")
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
                        choices: session.isYourMove ? session.gameState?.choices ?? [] : [],
                        activity: session.isStreaming ? .some(session.turns.last?.activity) : nil,
                        prompt: session.isStreaming ? session.turns.last?.pendingPrompt : nil,
                        agent: agentName,
                        answer: { session.answer($0, with: $1) }
                    ) { choice in
                        session.choose(choice)
                        isInputFocused = true
                    }
                } else {
                    ForEach(session.turns) { turn in
                        TurnView(
                            turn: turn,
                            isAnswering: session.isStreaming && turn.id == session.turns.last?.id,
                            agent: agentName,
                            answer: { session.answer($0, with: $1) }
                        )
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { conversationHeight = $0 }
        }
        .frame(height: min(conversationHeight, layout.maximumConversationHeight))
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let game = session.game, let state = session.gameState {
                Label(state.status, systemImage: game.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(session.isYourMove ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            } else if let provider = preferences.activeProvider {
                Label(preferences[provider].model.isEmpty ? provider.name : preferences[provider].model, systemImage: provider.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if session.isStreaming {
                Button(action: session.stop) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Stop")
                        Text("esc").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Stop answering")
            } else if session.isPlaying {
                if session.canHint {
                    FooterButton(title: "Hint", symbol: "lightbulb", shortcut: KeyboardShortcut("i")) {
                        session.hint()
                        isInputFocused = true
                    }
                    .help("Show a hint for your move")
                }
                FooterButton(title: "Copy", symbol: "doc.on.clipboard", shortcut: KeyboardShortcut("c", modifiers: [.command, .shift])) {
                    session.copyConversation()
                }
                .disabled(session.conversationMarkdown == nil)
                .help("Copy the game as plain text")
                FooterButton(title: "End Game", symbol: "square.and.pencil", shortcut: KeyboardShortcut("n")) {
                    session.reset()
                    isInputFocused = true
                }
            } else {
                FooterButton(title: "Copy Answer", symbol: "doc.on.doc", shortcut: KeyboardShortcut("c", modifiers: [.command, .shift])) {
                    session.copyLastAnswer()
                }
                .disabled(session.lastAnswer == nil)
                FooterButton(title: "Copy Conversation", symbol: "doc.on.clipboard", shortcut: KeyboardShortcut("c", modifiers: [.command, .shift, .option])) {
                    session.copyConversation()
                }
                .disabled(session.conversationMarkdown == nil)
                .help("Copy the whole chat as Markdown")
                FooterButton(title: "New Chat", symbol: "square.and.pencil", shortcut: KeyboardShortcut("n")) {
                    session.reset()
                    isInputFocused = true
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in session.attach(fileAt: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        if let image = NSImage(data: data) { session.attach(image) }
                    }
                }
            }
        }
        return accepted
    }
}

/// The sparkle menu: the ready providers of the current mode, and Recent Chats. The toggle under the
/// input switches modes, and the games have their own buttons beside it.
private struct ProviderMenu: View {
    let preferences: Preferences
    let session: ChatSession
    let openSettings: (SettingsPane?) -> Void
    let focusInput: () -> Void

    var body: some View {
        Menu {
            let kind = preferences.mode
            let ready = preferences.readyProviders(for: kind)
            let active = preferences.activeProvider
            Section(kind.pluralTitle) {
                if ready.isEmpty {
                    Text("No \(kind.pluralTitle) are turned on")
                    Button("Set Up \(kind.pluralTitle)…") { openSettings(.provider(kind.providers[0])) }
                }
                ForEach(ready) { provider in
                    Toggle(isOn: Binding(
                        get: { provider == active },
                        set: { if $0 { preferences.provider = provider } }
                    )) {
                        Label(provider.name, systemImage: provider.symbol)
                        let settings = preferences[provider]
                        let model = settings.model.isEmpty ? "Default model" : settings.model
                        let servers = settings.allowedMCPServers.count
                        Text(servers > 0 ? "\(model) · \(servers) MCP server\(servers == 1 ? "" : "s")" : model)
                    }
                }
            }
            Section("Recent Chats") {
                if session.history.isEmpty {
                    Text("No recent chats")
                }
                ForEach(session.history) { chat in
                    Button {
                        session.reopen(chat.id)
                        focusInput()
                    } label: {
                        Text(chat.title)
                        Text(chat.date, format: .relative(presentation: .named))
                    }
                }
            }
        } label: {
            Image(systemName: "sparkle")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.meraline)
                .symbolEffect(.pulse, isActive: session.isStreaming)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a provider or reopen a recent chat")
        .accessibilityLabel("Provider")
    }
}

private struct TurnView: View {
    let turn: ChatSession.Turn
    let isAnswering: Bool
    let agent: String
    let answer: (AgentPrompt.ID, AgentAnswer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !turn.question.isEmpty {
                Text(turn.question)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !turn.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(turn.images) { AttachmentThumbnail(image: $0, size: 40) }
                }
            }
            if !turn.answer.isEmpty {
                Text(MarkdownText.render(turn.answer))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let prompt = turn.pendingPrompt {
                PromptCard(prompt: prompt, agent: agent) { answer(prompt.id, $0) }
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
                ToolTrail(tools: turn.tools)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An agent's ask, with the means to settle it: Allow and Deny for a tool, or a question's choices as
/// buttons and a field for an answer of your own. One question with single choices is answered by the
/// first tap; several, or several choices, wait for Done. Neutral glass, with the panel's faint pink on
/// the default choice.
private struct PromptCard: View {
    let prompt: AgentPrompt
    let agent: String
    let answer: (AgentAnswer) -> Void
    /// The labels picked so far, by question.
    @State private var picks: [String: [String]] = [:]
    /// Answers typed instead of picked, by question.
    @State private var typed: [String: String] = [:]

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
            Button("Deny") { answer(.deny) }
                .buttonStyle(.glass)
            Button("Allow") { answer(.allow) }
                .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                .keyboardShortcut(.defaultAction)
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
                            .help(option.detail ?? option.label)
                    }
                }
            }
            TextField("Something else…", text: typedBinding(question))
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
        .help(text)
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

/// The tools an answer used, as small capsules under it: a web search, a page, a command, or an MCP tool
/// under its server's name. Hovering shows the full line. Neutral glass, like everything else here.
private struct ToolTrail: View {
    let tools: [Activity]

    var body: some View {
        FlowLayout(spacing: 6, maximumItemWidth: 260) {
            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                Label(tool.label, systemImage: tool.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .help(tool.title)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Used \(tools.map(\.label).formatted(.list(type: .and)))")
    }
}

/// Lays children out left to right and wraps to the next line when the row is full. Each child is
/// offered at most `maximumItemWidth`, so a long label truncates instead of taking a whole row.
private nonisolated struct FlowLayout: Layout {
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
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { GameLineView(line: $0) }
            if let prompt {
                PromptCard(prompt: prompt, agent: agent) { answer(prompt.id, $0) }
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
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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

private struct DraftImageTray: View {
    let images: [ImageAttachment]
    let onRemove: (ImageAttachment.ID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(images) { image in
                AttachmentThumbnail(image: image, size: 48)
                    .overlay(alignment: .topTrailing) {
                        Button { onRemove(image.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 18, height: 18)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove image")
                        .offset(x: 6, y: -6)
                    }
            }
            Spacer()
        }
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

/// What to do when the current mode has nothing ready: connect an LLM, or turn on an agent.
private struct SetupRow: View {
    let kind: ProviderKind
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind == .agent ? "terminal" : "key.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .agent ? "Turn on an agent" : "Connect an AI provider")
                    .font(.system(size: 13, weight: .semibold))
                Text(kind == .agent
                    ? "Install Claude Code, Codex, or OpenCode, then turn it on in Settings."
                    : "Add an API key or turn on a local model to start asking.")
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

private struct FooterButton: View {
    let title: String
    let symbol: String
    let shortcut: KeyboardShortcut
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: symbol)
                Text(shortcut.displayName)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .keyboardShortcut(shortcut)
    }
}

private extension KeyboardShortcut {
    var displayName: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + String(key.character).uppercased()
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
