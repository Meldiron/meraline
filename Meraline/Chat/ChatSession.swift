import AppKit
import Observation

@Observable
final class ChatSession {
    /// What the open chat is: quick questions, or one of the games under the input (see `Game`).
    enum Mode: Equatable {
        case chat
        case game(Game)
    }

    /// A question and its answer. In a game, a move and the model's reply (see `GameRules`).
    nonisolated struct Turn: Identifiable, Equatable, Sendable {
        let id = UUID()
        let question: String
        let images: [ImageAttachment]
        /// Files for an agent, copied into the chat's workspace when the question was sent.
        var files: [FileAttachment] = []
        /// Text selected in other apps, or copied, that the question was asked about.
        var selections: [SelectedText] = []
        var answer = ""
        var activity: Activity?
        /// The tools the model used for this answer, in order: searches, pages, commands, MCP tools.
        var tools: [Activity] = []
        /// What the agent stopped to ask during this answer, each with how it was settled.
        var prompts: [AgentPrompt] = []
        var isComplete = false
        var startsOverOnNextText = false
        /// In a game, what the model was asked when it moved on its own; nil for a move of yours.
        var cue: String?
        /// In a game, how the round settled on this Mac.
        var outcome: GameOutcome?

        /// The ask the agent is waiting on, if any.
        var pendingPrompt: AgentPrompt? { prompts.last(where: \.isPending) }
    }

    struct PastChat: Identifiable, Equatable {
        let id = UUID()
        let turns: [Turn]
        let date: Date
        var mode = Mode.chat
        /// The folder an agent worked in, kept with the chat so reopening it brings the files back.
        var workspace: ChatWorkspace?

        var title: String {
            let question = turns.first?.question ?? ""
            switch mode {
            case .chat:
                return question.isEmpty ? turns.first?.selections.first?.excerpt ?? turns.first?.files.first?.name ?? "Image question" : question
            case .game(let game):
                return game.rules.headline(of: turns).map { "\(game.title): \($0)" } ?? game.title
            }
        }
    }

    static let historyLimit = 5

    var draft = ""
    private(set) var draftImages: [ImageAttachment] = []
    private(set) var draftFiles: [FileAttachment] = []
    /// Text selected in other apps, or copied, for the next question, in the order it came (see `bring(_:)`).
    /// Only you put it here: the selection button, the clipboard button, the Services menu, or
    /// `meraline://ask?selection=`.
    private(set) var draftSelections: [SelectedText] = []
    /// The text selected in the app in front when the shortcut opened the window. It stays out of the draft
    /// until the selection button above the card adds it (see `toggleOfferedSelection()`).
    private(set) var offeredSelection: SelectedText?
    /// The images and files the last Finder selection brought (see `bring(files:)`), which the next one replaces.
    @ObservationIgnored private var broughtAttachments: Set<UUID> = []
    private(set) var turns: [Turn] = []
    private(set) var history: [PastChat] = []
    private(set) var mode = Mode.chat
    /// The folder an agent works in for this chat, made on the first question to one.
    private(set) var workspace: ChatWorkspace?
    private(set) var isStreaming = false
    private(set) var failure: String?
    private(set) var failureNeedsSettings = false
    /// A friendly line from a game: its invitation, why a move came back, or that the round is over.
    /// Unlike `failure`, nothing went wrong.
    private(set) var nudge: String?
    /// How each game has gone against the model since Meraline opened, for the rematch tray. In memory
    /// only, like Recent Chats, so quitting forgets it.
    private(set) var versus: [Game: Versus] = [:]
    /// The game the rematch tray offers again once it ends: the one started or reopened last, until the
    /// tray is put away.
    private(set) var lastGame: Game?
    /// Anonymous mode: the open chat skips Recent Chats when it ends, and its workspace goes with it. It
    /// decides the fate of whatever chat is open when the chat ends, so turning it on mid-chat keeps that
    /// chat out too. It lasts until turned off or until Meraline quits, and is never saved.
    var isAnonymous = false {
        didSet {
            guard isAnonymous != oldValue else { return }
            Log.chat.info("Anonymous mode \(isAnonymous ? "on" : "off")")
        }
    }

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    /// The game move that came back last; sending it again unchanged insists on it.
    @ObservationIgnored private var insistedInput: String?
    /// The answer Ask Again is replacing, which comes back if the new one brings no text.
    @ObservationIgnored private var replacedTurn: Turn?
    /// How to answer each prompt the agent is waiting on, by the prompt's id.
    @ObservationIgnored private var responders: [String: AgentPromptResponder] = [:]
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let workspaceRoot: URL
    @ObservationIgnored private let streamReplies: @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error>

    /// `stream` talks to the provider; tests pass one that replies on its own, and their own
    /// `workspaceRoot` so they never touch the app's workspaces.
    init(
        preferences: Preferences,
        workspaceRoot: URL = ChatWorkspace.defaultRoot,
        stream: @escaping @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> = LLMClient.stream
    ) {
        self.preferences = preferences
        self.workspaceRoot = workspaceRoot
        streamReplies = stream
    }

    var canSend: Bool {
        guard !isStreaming else { return false }
        guard let gameState else {
            return fileNotice == nil && (!draft.trimmed.isEmpty || !draftImages.isEmpty || !draftFiles.isEmpty || !draftSelections.isEmpty)
        }
        switch gameState.phase {
        case .modelMoves, .over: return true
        case .yourMove: return !draft.trimmed.isEmpty
        case .waiting: return false
        }
    }

    /// The game being played, or nil in an ordinary chat.
    var game: Game? {
        if case .game(let game) = mode { game } else { nil }
    }

    var isPlaying: Bool { game != nil }

    /// Where the game stands, worked out from the turns by its rules.
    var gameState: GameState? { game?.rules.state(of: turns) }

    /// The game is waiting for you.
    var isYourMove: Bool { !isStreaming && gameState?.isYourMove == true }

    /// The game has a hint for your move.
    var canHint: Bool { isYourMove && gameState?.hints.isEmpty == false }

    var lastAnswer: String? {
        turns.last(where: { !$0.answer.isEmpty })?.answer
    }

    /// Why the draft waits: it has files, which only an agent reads, and the panel is asking an LLM.
    /// Switching to Agent sends them as they are.
    var fileNotice: String? {
        guard preferences.mode == .llm, !draftFiles.isEmpty else { return nil }
        let kinds = FileAttachment.kinds(of: draftFiles)
        return "Only an agent can read \(kinds). Switch to Agent to send \(draftFiles.count == 1 ? "it" : "them")."
    }

    func send() {
        guard canSend else { return }
        if let game {
            play(game)
            return
        }
        guard let provider = preferences.activeProvider else {
            fail(with: setupMessage(to: "start asking"), needsSettings: true)
            return
        }
        let question = draft.trimmed
        let images = draftImages
        let files = draftFiles
        let selections = draftSelections
        let request = makeRequest(asking: SelectedText.message(question, about: selections), images: images, files: files, of: provider)

        draft = ""
        draftImages = []
        draftFiles = []
        draftSelections = []
        failure = nil
        let turn = Turn(question: question, images: images, files: files, selections: selections)
        turns.append(turn)
        isStreaming = true
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))), turn \(turns.count), \(images.count) image(s), \(files.count) file(s), \(selections.count) text(s)")
        stream(request, for: turn.id)
    }

    /// Whether Ask Again can ask the last question once more: a chat, not a game, whose last answer is done.
    var canAskAgain: Bool {
        !isStreaming && !isPlaying && turns.last?.isComplete == true && preferences.activeProvider != nil
    }

    /// Asks the last question again, of the provider in use now, for an answer in place of the last one.
    /// Whatever is typed in the input stays there.
    func askAgain() {
        guard canAskAgain, let provider = preferences.activeProvider, let last = turns.popLast() else { return }
        replacedTurn = last
        let request = makeRequest(asking: SelectedText.message(last.question, about: last.selections), images: last.images, files: last.files, of: provider)
        failure = nil
        let turn = Turn(question: last.question, images: last.images, files: last.files, selections: last.selections)
        turns.append(turn)
        isStreaming = true
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))) again, turn \(turns.count)")
        stream(request, for: turn.id)
    }

    /// What Return does in a game: asks the model for its move, starts the next round, or plays your line.
    private func play(_ game: Game) {
        switch game.rules.state(of: turns).phase {
        case .modelMoves(let cue):
            askModel(cue, in: game)
        case .over(_, let rematch):
            askModel(rematch.cue, in: game)
        case .waiting:
            break
        case .yourMove:
            let input = draft.trimmed
            let move = game.rules.play(input, in: turns, insisting: input == insistedInput)
            insistedInput = nil
            switch move {
            case .reject(let message):
                Log.chat.info("\(game.title): your move came back")
                nudge = message
                insistedInput = input
            case .ask(let line):
                guard let provider = preferences.activeProvider else {
                    fail(with: setupMessage(to: "play"), needsSettings: true)
                    return
                }
                let request = makeRequest(asking: line, images: [], of: provider)
                draft = ""
                failure = nil
                nudge = nil
                let turn = Turn(question: line, images: [])
                turns.append(turn)
                isStreaming = true
                Log.chat.info("\(game.title): your move to \(provider.name) (\(modelName(for: provider))), turn \(turns.count)")
                stream(request, for: turn.id)
            case .record(let line, let outcome):
                draft = ""
                failure = nil
                nudge = nil
                turns.append(Turn(question: line, images: [], isComplete: true, outcome: outcome))
                Log.chat.info("\(game.title): your move kept, turn \(turns.count)")
                advance(game, asksModel: true)
            case .settle(let outcome):
                guard !turns.isEmpty else { return }
                draft = ""
                failure = nil
                nudge = nil
                turns[turns.count - 1].outcome = outcome
                Log.chat.info("\(game.title): round settled, turn \(turns.count)")
                advance(game, asksModel: true)
            }
        }
    }

    /// After a move: asks the model when it moves next, and says so when the round is over.
    private func advance(_ game: Game, asksModel: Bool) {
        switch game.rules.state(of: turns).phase {
        case .modelMoves(let cue) where asksModel:
            askModel(cue, in: game)
        case .over(let outcome, _):
            Log.chat.info("\(game.title): round over")
            versus[game, default: Versus()].record(outcome)
            nudge = outcome.text
        default:
            break
        }
    }

    /// Asks the model for a move of its own: a turn with a cue and nothing of yours. If that fails,
    /// Return asks again.
    private func askModel(_ cue: String, in game: Game) {
        guard let provider = preferences.activeProvider else {
            fail(with: setupMessage(to: "play"), needsSettings: true)
            return
        }
        let request = makeRequest(asking: cue, images: [], of: provider)
        failure = nil
        nudge = nil
        let turn = Turn(question: "", images: [], cue: cue)
        turns.append(turn)
        isStreaming = true
        Log.chat.info("\(game.title): \(provider.name) (\(modelName(for: provider))) moves, turn \(turns.count)")
        stream(request, for: turn.id)
    }

    /// What to set up when the current mode has nothing ready.
    private func setupMessage(to goal: String) -> String {
        switch preferences.mode {
        case .llm: "Connect an AI provider in Settings to \(goal)."
        case .agent: "Turn on an agent in Settings to \(goal), or switch to LLM."
        }
    }

    private func modelName(for provider: Provider) -> String {
        let model = preferences[provider].model.trimmed
        return model.isEmpty ? "default model" : model
    }

    private func stream(_ request: ChatRequest, for id: Turn.ID) {
        let replies = streamReplies(request)
        streamTask = Task { [weak self] in
            do {
                for try await output in replies {
                    self?.receive(output, for: id)
                }
                self?.finishStreaming(id, error: Task.isCancelled ? CancellationError() : nil)
            } catch {
                self?.finishStreaming(id, error: error)
            }
        }
    }

    /// The request a question or a game move makes. A game sends its own prompt and the cue of each move
    /// the model made on its own; the prompt from Settings stays out of it. Two messages in a row from one
    /// side, which a game can leave, are joined into one.
    func makeRequest(asking question: String, images: [ImageAttachment], files: [FileAttachment] = [], of provider: Provider) -> ChatRequest {
        var messages: [ChatMessage] = []
        func add(_ role: ChatMessage.Role, _ text: String, _ images: [ImageAttachment] = [], _ files: [FileAttachment] = []) {
            guard !text.isEmpty || !images.isEmpty || !files.isEmpty else { return }
            if let previous = messages.last, previous.role == role {
                let joined = [previous.text, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                messages[messages.count - 1] = ChatMessage(role: role, text: joined, images: previous.images + images, files: previous.files + files)
            } else {
                messages.append(ChatMessage(role: role, text: text, images: images, files: files))
            }
        }
        for turn in turns where turn.isComplete {
            add(.user, turn.cue ?? SelectedText.message(turn.question, about: turn.selections), turn.images, turn.files)
            add(.assistant, turn.answer)
        }
        add(.user, question, images, files)
        return ChatRequest(
            provider: provider,
            settings: preferences[provider],
            systemPrompt: game?.rules.systemPrompt ?? preferences.systemPrompt,
            messages: messages,
            workspace: provider.isCommandLine ? workspaceForAgents()?.url : nil
        )
    }

    /// The chat's workspace, made on the first question to an agent.
    private func workspaceForAgents() -> ChatWorkspace? {
        if let workspace { return workspace }
        do {
            workspace = try ChatWorkspace.make(in: workspaceRoot)
            Log.chat.info("Workspace made for this chat")
        } catch {
            Log.chat.error("Couldn’t make a workspace: \(error.localizedDescription)")
        }
        return workspace
    }

    /// Answers the ask an agent is waiting on: leave to use a tool, or its question.
    func answer(_ promptID: AgentPrompt.ID, with answer: AgentAnswer) {
        guard let responder = responders.removeValue(forKey: promptID),
              let last = turns.indices.last,
              let index = turns[last].prompts.firstIndex(where: { $0.id == promptID }) else { return }
        turns[last].prompts[index].resolution = answer.resolution
        switch answer {
        case .allow: Log.chat.info("Agent's ask allowed")
        case .deny: Log.chat.info("Agent's ask denied")
        case .answers: Log.chat.info("Agent's question answered")
        }
        responder(answer)
    }

    func stop() {
        guard isStreaming else { return }
        streamTask?.cancel()
    }

    /// Starts a new chat. The open one moves to Recent Chats, unless `keepingChat` is false or the chat is
    /// anonymous.
    func reset(keepingChat: Bool = true) {
        archiveCurrentChat(keeping: keepingChat)
        streamTask?.cancel()
        streamTask = nil
        responders = [:]
        replacedTurn = nil
        draft = ""
        draftImages = []
        draftFiles = []
        draftSelections = []
        turns = []
        mode = .chat
        isStreaming = false
        failure = nil
        failureNeedsSettings = false
        nudge = nil
        insistedInput = nil
    }

    /// Deletes the open chat or game: it skips Recent Chats, and its workspace goes with it. A game's score
    /// against the model stays.
    func deleteChat() {
        let kind = isPlaying ? "Game" : "Chat"
        reset(keepingChat: false)
        Log.chat.info("\(kind) deleted")
    }

    /// Starts a game in place of the open chat, which moves to Recent Chats first. The model moves first.
    func startGame(_ game: Game) {
        reset()
        mode = .game(game)
        lastGame = game
        Log.chat.info("\(game.title) started")
        advance(game, asksModel: true)
        nudge = game.rules.invitation
    }

    /// Plays one of a game's buttons, such as a word to pick.
    func choose(_ choice: String) {
        guard isYourMove else { return }
        draft = choice
        send()
    }

    /// Shows one of the game's hints for your move at random, never the one showing already.
    func hint() {
        guard let game, isYourMove, let hints = gameState?.hints else { return }
        let others = hints.filter { $0 != nudge }
        guard let hint = (others.isEmpty ? hints : others).randomElement() else { return }
        nudge = hint
        Log.chat.info("\(game.title): hint shown")
    }

    /// What the rematch tray offers: the game's next round once one is over, or the last game again on an
    /// empty panel after it ended.
    var rematch: RematchOffer? {
        if let game, !isStreaming, case .over(let outcome, _)? = gameState?.phase {
            return RematchOffer(game: game, message: nudge ?? outcome.text, versus: versus[game] ?? Versus(), isAfterGame: false)
        }
        guard !isPlaying, turns.isEmpty, let lastGame else { return nil }
        return RematchOffer(game: lastGame, message: lastGame.title, versus: versus[lastGame] ?? Versus(), isAfterGame: true)
    }

    /// Play Again in the rematch tray: the next round, like Return, or the last game started over.
    func playAgain() {
        guard let rematch else { return }
        if rematch.isAfterGame {
            startGame(rematch.game)
        } else {
            send()
        }
    }

    /// Takes the rematch tray off the empty panel until the next game. The tally stays.
    func putAwayRematch() {
        lastGame = nil
    }

    func reopen(_ id: PastChat.ID) {
        guard let chat = history.first(where: { $0.id == id }) else { return }
        history.removeAll { $0.id == id }
        reopen(chat)
    }

    /// Makes a past chat the open one, in the mode it was in. Whatever was open moves to Recent Chats.
    /// The chat leaves Recent Chats, so its workspace belongs to one chat only.
    func reopen(_ chat: PastChat) {
        history.removeAll { $0.id == chat.id }
        reset()
        turns = chat.turns
        mode = chat.mode
        workspace = chat.workspace
        if case .game(let game) = mode { lastGame = game }
        if case .over(let outcome, _)? = gameState?.phase { nudge = outcome.text }
    }

    /// The window came back after being hidden for a long time: the chat moves to Recent Chats and the
    /// next question starts fresh. Anything typed but not yet sent stays in the input. A game ends.
    func expire() {
        guard !isStreaming, !turns.isEmpty || isPlaying else { return }
        archiveCurrentChat()
        turns = []
        mode = .chat
        failure = nil
        failureNeedsSettings = false
        nudge = nil
        insistedInput = nil
    }

    /// Moves the chat to Recent Chats with its workspace, unless the chat is anonymous or not `keeping`. A
    /// workspace whose chat is not kept, and those of the chats that drop off the end, are removed.
    private func archiveCurrentChat(keeping: Bool = true) {
        let previous = history
        if keeping && !isAnonymous {
            history = Self.archiving(turns, into: history, mode: mode, workspace: workspace)
        }
        let kept = Set(history.map(\.id))
        for chat in previous where !kept.contains(chat.id) { chat.workspace?.remove() }
        if let workspace, !history.contains(where: { $0.workspace == workspace }) { workspace.remove() }
        workspace = nil
    }

    static func archiving(_ turns: [Turn], into history: [PastChat], mode: Mode = .chat, at date: Date = .now, workspace: ChatWorkspace? = nil) -> [PastChat] {
        let answered = turns
            .filter { !$0.answer.isEmpty || $0.isComplete }
            .map { turn in
                var turn = turn
                turn.activity = nil
                turn.prompts.removeAll(where: \.isPending)
                turn.isComplete = true
                return turn
            }
        guard !answered.isEmpty else { return history }
        return Array(([PastChat(turns: answered, date: date, mode: mode, workspace: workspace)] + history).prefix(historyLimit))
    }

    /// Forgets the recent chats, workspaces and all, and says how many went. The open chat stays.
    @discardableResult
    func forgetHistory() -> Int {
        let count = history.count
        for chat in history { chat.workspace?.remove() }
        history = []
        if count > 0 { Log.chat.info("\(count) recent chat(s) forgotten") }
        return count
    }

    func clearDraft() {
        draft = ""
        draftImages = []
        draftFiles = []
        draftSelections = []
        failure = nil
    }

    func attach(_ image: NSImage) {
        attach { try ImageAttachment.make(from: image) }
    }

    /// A file from Finder or the pasteboard. An image goes in as one, for either mode; anything else, an
    /// image Meraline can't read included, is a file for an agent.
    func attach(fileAt url: URL) {
        // An image that can't go in is turned away before it is read, so pasting a hundred photos doesn't
        // decode every one of them only to keep five.
        if ImageAttachment.isImage(at: url), isPlaying || draftImages.count >= ImageAttachment.limit {
            attach { try ImageAttachment.load(from: url) }
            return
        }
        if let image = try? ImageAttachment.load(from: url) {
            attach { image }
            return
        }
        guard !isPlaying else {
            nudge = Game.noImages
            return
        }
        guard !draftFiles.contains(where: { $0.url.path == url.resolvingSymlinksInPath().path }) else { return }
        do {
            draftFiles.append(try FileAttachment.make(from: url, avoiding: fileNamesInUse))
            failure = nil
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    /// The names taken in the chat's workspace: the chat's files, and whatever the agent keeps there.
    private var fileNamesInUse: [String] {
        let files = (turns.flatMap(\.files) + draftFiles).map(\.name)
        let kept = workspace.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.url.path) } ?? []
        return files + kept
    }

    /// Text selected in another app, or copied, for the next question, after whatever text is there already.
    /// The same text from the same place comes only once. A game has no use for it.
    func bring(_ selection: SelectedText) {
        guard !isPlaying, !draftSelections.contains(where: { $0.isSame(as: selection) }) else { return }
        draftSelections.append(selection)
        failure = nil
    }

    /// Leaves one text out of the next question.
    func removeSelection(_ id: SelectedText.ID) {
        draftSelections.removeAll { $0.id == id }
    }

    /// The shortcut opened the window with what is selected now. Selected text is only offered, for the
    /// selection button to add; Finder files come into the draft in place of whatever an earlier selection
    /// brought, and with nothing selected those go too, so the window never holds a selection you have since
    /// let go of. Whatever you added yourself stays.
    func bringCurrentSelection(text: SelectedText?, files: [URL]) {
        guard !isPlaying else { return }
        offeredSelection = text
        bring(files: files)
    }

    /// The selection button: the offered text joins the draft, or leaves it when the same text is there
    /// already. It stays on offer either way, so the button can bring it back. False when nothing is on offer.
    @discardableResult
    func toggleOfferedSelection() -> Bool {
        guard !isPlaying, let offeredSelection else { return false }
        if let added = draftSelections.first(where: { $0.isSame(as: offeredSelection) }) {
            removeSelection(added.id)
        } else {
            bring(offeredSelection)
        }
        return true
    }

    /// Whether the offered text is in the draft already, so the selection button would take it out.
    var isOfferedSelectionAdded: Bool {
        guard let offeredSelection else { return false }
        return draftSelections.contains { $0.isSame(as: offeredSelection) }
    }

    /// The window closed: what was selected when it opened is no longer on offer.
    func withdrawOfferedSelection() {
        offeredSelection = nil
    }

    /// What the clipboard button found: copied files and pictures come in as attachments, as ⌘V brings them,
    /// and text waits in a card of its own, after any text there. Returns the draft's items that hold it now,
    /// new or already there, so the button knows what to take out again. A game has no use for any of it.
    @discardableResult
    func addClipboard(_ content: ClipboardContent) -> Set<UUID> {
        let before = draftContextIDs
        switch content {
        case .files(let urls):
            urls.forEach(attach(fileAt:))
            let paths = Set(urls.map { $0.resolvingSymlinksInPath().path })
            let named = draftFiles.filter { paths.contains($0.url.path) }.map(\.id)
            return draftContextIDs.subtracting(before).union(named)
        case .image(let image):
            attach(image)
            return draftContextIDs.subtracting(before)
        case .text(let text):
            guard !isPlaying, let selection = SelectedText.clipboard(text) else { return [] }
            bring(selection)
            return Set(draftSelections.filter { $0.isSame(as: selection) }.map(\.id))
        }
    }

    /// Files and folders selected in Finder, in place of whatever the last selection brought. An image comes as
    /// one for either mode; anything else only while asking an agent, since an LLM can't read it, unless they
    /// were handed over `deliberately` (the Services menu), which brings everything, like a drop. A game has
    /// no use for them.
    func bring(files urls: [URL], deliberately: Bool = false) {
        guard !isPlaying else { return }
        let usable = deliberately || preferences.mode == .agent ? urls : urls.filter(ImageAttachment.isImage(at:))
        draftImages.removeAll { broughtAttachments.contains($0.id) }
        draftFiles.removeAll { broughtAttachments.contains($0.id) }
        let before = attachmentIDs
        usable.forEach(attach(fileAt:))
        broughtAttachments = attachmentIDs.subtracting(before)
    }

    private var attachmentIDs: Set<UUID> {
        Set(draftImages.map(\.id) + draftFiles.map(\.id))
    }

    /// Every text, image, and file waiting in the draft.
    var draftContextIDs: Set<UUID> {
        attachmentIDs.union(draftSelections.map(\.id))
    }

    /// Takes texts, images, and files out of the draft.
    func removeContext(_ ids: Set<UUID>) {
        draftSelections.removeAll { ids.contains($0.id) }
        draftImages.removeAll { ids.contains($0.id) }
        draftFiles.removeAll { ids.contains($0.id) }
    }

    /// ⌫ in an empty input: takes out the last text, or else the last file or image, like a token in
    /// Spotlight. False when there is nothing to take out.
    func removeLastContext() -> Bool {
        if !draftSelections.isEmpty {
            draftSelections.removeLast()
        } else if !draftFiles.isEmpty {
            draftFiles.removeLast()
        } else if !draftImages.isEmpty {
            draftImages.removeLast()
        } else {
            return false
        }
        return true
    }

    /// Takes an image or a file out of the draft.
    func removeAttachment(_ id: UUID) {
        draftImages.removeAll { $0.id == id }
        draftFiles.removeAll { $0.id == id }
    }

    func copyLastAnswer() {
        guard let lastAnswer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAnswer, forType: .string)
    }

    /// The chat as Markdown, or a game's own transcript.
    var conversationMarkdown: String? {
        if let game { return game.rules.transcript(of: turns) }
        return Self.markdown(for: turns)
    }

    func copyConversation() {
        guard let conversationMarkdown else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(conversationMarkdown, forType: .string)
    }

    /// Every answered turn as Markdown, so a long thread can leave the panel without anything being saved.
    static func markdown(for turns: [Turn]) -> String? {
        let answered = turns.filter { !$0.answer.isEmpty }
        guard !answered.isEmpty else { return nil }
        return answered.map { turn in
            var question = turn.question
            var attached: [String] = []
            if !turn.images.isEmpty { attached.append(turn.images.count == 1 ? "1 image" : "\(turn.images.count) images") }
            attached += turn.files.map(\.name)
            if !attached.isEmpty {
                let note = "\(attached.joined(separator: ", ")) attached"
                question += question.isEmpty ? "_\(note)_" : " _(\(note))_"
            }
            let asked = (turn.selections.map(\.markdownQuote) + [question]).filter { !$0.isEmpty }.joined(separator: "\n\n")
            return "**You**\n\n\(asked)\n\n**Assistant**\n\n\(turn.answer.trimmed)"
        }.joined(separator: "\n\n---\n\n")
    }

    private func attach(_ make: () throws -> ImageAttachment) {
        guard !isPlaying else {
            nudge = Game.noImages
            return
        }
        guard draftImages.count < ImageAttachment.limit else {
            fail(with: AttachmentError.limitReached.localizedDescription)
            return
        }
        do {
            draftImages.append(try make())
            failure = nil
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    private func receive(_ output: StreamOutput, for id: Turn.ID) {
        guard turns.last?.id == id else { return }
        let last = turns.count - 1
        switch output {
        case .activity(let activity):
            turns[last].activity = activity
            Self.record(activity, in: &turns[last].tools)
            turns[last].startsOverOnNextText = !turns[last].answer.isEmpty
        case .text(let text):
            if turns[last].startsOverOnNextText {
                turns[last].answer = text
                turns[last].startsOverOnNextText = false
            } else {
                turns[last].answer += text
            }
            turns[last].activity = nil
        case .prompt(let prompt, let responder):
            turns[last].prompts.append(prompt)
            turns[last].activity = nil
            if let responder {
                responders[prompt.id] = responder
                Log.chat.info("Agent asks \(prompt.kind.logDescription)")
            } else {
                Log.chat.info("Agent turned down its own ask \(prompt.kind.logDescription)")
            }
        }
    }

    /// Keeps the trail of tools an answer used. Thinking is not a tool. An agent often announces a tool
    /// twice, first by name and then with what it was asked, so a repeat of the last step fills it in
    /// rather than adding a second one; the same step with new details, like a second search, is added.
    nonisolated static func record(_ activity: Activity, in tools: inout [Activity]) {
        guard activity != .thinking else { return }
        if case .copying = activity { return }
        if let last = tools.last, last.isSameStep(as: activity) {
            if last == activity || activity.isVague { return }
            if last.isVague {
                tools[tools.count - 1] = activity
                return
            }
        }
        tools.append(activity)
    }

    private func finishStreaming(_ id: Turn.ID, error: Error?) {
        guard isStreaming, turns.last?.id == id else { return }
        isStreaming = false
        streamTask = nil
        responders = [:]
        let replaced = replacedTurn
        replacedTurn = nil
        let last = turns.count - 1
        turns[last].activity = nil
        turns[last].prompts.removeAll(where: \.isPending)
        if let game {
            finishMove(in: game, error: error)
            return
        }

        guard let error, !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
            turns[last].isComplete = !turns[last].answer.isEmpty
            if turns[last].answer.isEmpty {
                Log.chat.info("Answer stopped before any text arrived")
                takeBackQuestion(restoring: replaced)
            } else {
                Log.chat.info("Answer \(error == nil ? "complete" : "stopped"), \(turns[last].answer.count) characters")
            }
            return
        }
        Log.chat.error("Answer failed: \(error.localizedDescription)")

        if turns[last].answer.isEmpty {
            takeBackQuestion(restoring: replaced)
        } else {
            turns[last].isComplete = true
        }
        fail(with: error.localizedDescription, needsSettings: Self.needsSettings(error))
    }

    /// An answer that brought no text goes: its question returns to the input, or, when Ask Again asked it,
    /// the answer it was to replace comes back and the input stays as it is.
    private func takeBackQuestion(restoring replaced: Turn?) {
        let turn = turns.removeLast()
        if let replaced {
            turns.append(replaced)
        } else {
            restoreDraft(from: turn)
        }
    }

    /// A game move's reply is complete, stopped, or failed. A reply the game refuses sends the move back:
    /// the turn goes and what you typed returns to the input, so a refused move costs nothing.
    private func finishMove(in game: Game, error: Error?) {
        let last = turns.count - 1
        let wasStopped = error is CancellationError || (error as? URLError)?.code == .cancelled
        if let error, !wasStopped {
            Log.chat.error("\(game.title): the model's move failed: \(error.localizedDescription)")
            takeBackLastTurn()
            fail(with: error.localizedDescription, needsSettings: Self.needsSettings(error))
            return
        }
        guard !wasStopped, !turns[last].answer.trimmed.isEmpty else {
            Log.chat.info("\(game.title): the model's move stopped")
            takeBackLastTurn()
            return
        }
        switch game.rules.judge(turns[last].answer, in: turns) {
        case .accept(let reply):
            turns[last].answer = reply
            turns[last].isComplete = true
            Log.chat.info("\(game.title): the model moved, turn \(turns.count)")
            advance(game, asksModel: false)
        case .refuse(let message):
            Log.chat.info("\(game.title): the model's reply sent the move back")
            takeBackLastTurn()
            nudge = message
        }
    }

    /// Removes the last game turn and puts your line back in the input. A move of the model's own leaves
    /// the input as it is.
    private func takeBackLastTurn() {
        let turn = turns.removeLast()
        if !turn.question.isEmpty { draft = turn.question }
    }

    private static func needsSettings(_ error: Error) -> Bool {
        switch error as? LLMError {
        case .missingKey, .invalidBaseURL: true
        case .http(let status, _): status == 401 || status == 403 || status == 404
        default: false
        }
    }

    private func restoreDraft(from turn: Turn) {
        draft = turn.question
        draftImages = turn.images
        draftFiles = turn.files
        draftSelections = turn.selections
    }

    private func fail(with message: String, needsSettings: Bool = false) {
        failure = message
        failureNeedsSettings = needsSettings
    }
}
