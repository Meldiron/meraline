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
        /// The files the agent handed over with this answer, found in the chat's workspace.
        var presentedFiles: [PresentedFile] = []
        var isComplete = false
        var startsOverOnNextText = false
        /// In a game, what the model was asked when it moved on its own, or what told it that your move opens
        /// a round; nil for any other move of yours.
        var cue: String?
        /// In a game, what this Mac drew to go with the move, such as a story's subject or the words a line
        /// may end on (see `GameDice`). The model reads it after the move; the transcript never shows it.
        var aside: String?
        /// In a game, how the round settled on this Mac.
        var outcome: GameOutcome?
        /// A warning that goes with this question, such as the chat's folder having been cleared.
        var notice: String?
        /// The provider the question went to, for the count of usage.
        var provider: Provider?
        /// When the question was sent, for how long its answer took.
        var sentAt = Date.now
        /// Roughly how many tokens the request was, for when the provider reports none.
        var estimatedInput = 0
        /// What the provider said the answer took, as it came; nil when it said nothing.
        var usage: TokenUsage?
        /// What the answer changed in the text its question was about, found when it ended, for Show What Changed;
        /// nil when it isn't that text changed (see `TextChanges`).
        var changes: TextChanges?
        /// What Jev decided, for a question asked in Decision mode; `answer` then says it in words (see `Decision`).
        var decision: Decision?
        /// What Jev decided about each word or line, for a question asked about each (see `DecisionBatch`), filled
        /// in as the batches come; `answer` then sums it up.
        var decisions: DecisionBatch?
        /// What Jev decided about each of Decision's presets, asked at once (see `PresetDecisions`): the round, with
        /// no decision yet, from the moment the question goes, so the card shows what is asked, then filled in as
        /// the replies come; `answer` then sums it up.
        var presetDecisions: PresetDecisions?

        /// The answer is a decision, about the text, each of its words or lines, or each preset, not words of a
        /// model's.
        var isDecision: Bool { decision != nil || decisions != nil || presetDecisions != nil }

        /// The ask the agent is waiting on, if any.
        var pendingPrompt: AgentPrompt? { prompts.last(where: \.isPending) }

        /// Roughly how much memory the turn takes: its pictures, mostly, and its text.
        var byteCount: Int {
            images.reduce(0) { $0 + $1.data.count } + question.utf8.count + answer.utf8.count
                + selections.reduce(0) { $0 + $1.text.utf8.count } + (cue?.utf8.count ?? 0) + (aside?.utf8.count ?? 0)
        }

        /// What the model is sent for this turn: the cue, the question after the text it is about, and the aside.
        var message: String {
            [cue ?? "", SelectedText.message(question, about: selections), aside ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }

    /// A question not asked yet: what is typed, and the texts, images, and files added for it.
    struct Draft: Equatable {
        var text = ""
        var images: [ImageAttachment] = []
        var files: [FileAttachment] = []
        var selections: [SelectedText] = []
        /// Text written in the window for a decision (see `TypedStateCard`), or nil while its card is closed.
        var typedState: String?
        /// The Live switch's questions and answers, when it was on (see `LiveDecisions.Snapshot`).
        var live: LiveDecisions.Snapshot?

        var isEmpty: Bool {
            text.trimmed.isEmpty && images.isEmpty && files.isEmpty && selections.isEmpty && (typedState ?? "").trimmed.isEmpty
                && (live?.keptQuestions.isEmpty ?? true)
        }

        /// The draft as the question it would ask, the written text among its texts.
        var turn: Turn {
            Turn(question: text.trimmed, images: images, files: files, selections: selections + (typedState.flatMap(SelectedText.typed).map { [$0] } ?? []))
        }
    }

    struct PastChat: Identifiable, Equatable {
        let id = UUID()
        let turns: [Turn]
        let date: Date
        var mode = Mode.chat
        /// The folder an agent worked in, kept with the chat so reopening it brings the files back.
        var workspace: ChatWorkspace?
        /// What reopening puts back in the input: a draft Stash Draft parked here in place of a conversation, or
        /// one the chat had while Live decisions were on (see `reset(keepingChat:)`).
        var draft: Draft?
        /// When the chat goes, workspace and all: its time kept running from when it was open.
        var expiresAt = Date.now.addingTimeInterval(ChatSession.chatLifetime)

        /// A draft parked on its own, with no conversation.
        var isStash: Bool { turns.isEmpty && draft != nil }

        var title: String {
            let first = turns.first ?? draft?.turn
            let question = first?.question ?? ""
            switch mode {
            case .chat:
                return question.isEmpty
                    ? first?.selections.first?.excerpt ?? first?.files.first?.name ?? draft?.live?.keptQuestions.first?.text ?? "Image question"
                    : question
            case .game(let game):
                return game.rules.headline(of: turns).map { "\(game.title): \($0)" } ?? game.title
            }
        }

        /// Roughly how much memory the chat takes, a stashed draft's pictures included.
        var byteCount: Int {
            ChatSession.byteCount(of: turns) + (draft?.turn.byteCount ?? 0)
        }
    }

    /// How long a chat lasts after its last message, open or in Recent Chats, before it goes with its workspace.
    /// A message or the end of an answer starts it over, unless the buttons beside the timer under the card left
    /// it more; reopening the chat doesn't.
    static let chatLifetime: TimeInterval = 30 * 60
    /// The most chats in memory, the open one included, and so the most workspaces on disk. Recent Chats lets go
    /// of its oldest to stay under it.
    static let chatLimit = 1_000
    /// The most memory one chat may take, pictures mostly. A question that would take it past this doesn't go.
    static let chatByteLimit = 512 * 1_024 * 1_024
    /// How long streamed text waits at most before it joins its answer (see `hold(_:)`). An answer is laid out
    /// again each time it grows, which takes longer the longer it is, so the words that come within this of each
    /// other go in together: a long answer that streams fast then shows as fast as it comes.
    static let textInterval: Duration = .milliseconds(50)

    var draft = "" {
        didSet {
            // A colon typed at the end of the question says the text comes next, so the card for writing it
            // opens by itself (see `writeStateAfterColon()`).
            if Self.endsInColon(draft), !Self.endsInColon(oldValue) { writeStateAfterColon() }
            if draft != oldValue { refreshLiveDecisions() }
        }
    }
    private(set) var draftImages: [ImageAttachment] = []
    private(set) var draftFiles: [FileAttachment] = []
    /// Text selected in other apps, or copied, for the next question, in the order it came (see `bring(_:)`).
    /// Only you put it here: the selection button, the clipboard button, the Services menu, or
    /// `meraline://ask?selection=`.
    private(set) var draftSelections: [SelectedText] = [] {
        didSet { refreshLiveDecisions() }
    }
    /// The text selected in the app in front when the shortcut opened the window. It stays out of the draft
    /// until the selection button above the card adds it (see `toggleOfferedSelection()`).
    private(set) var offeredSelection: SelectedText?
    /// Text written in the window for a decision, while its card is open (see `writeState()`): nil until Write It
    /// opens the card, and empty from then until something is typed. It goes with the question as a text of its
    /// own (`SelectedText.typed`).
    var typedState: String? {
        didSet {
            guard typedState != oldValue else { return }
            refreshLiveDecisions()
            // A change of the text, by hand or by Improve, puts away what the last Improve had to say; the card
            // closing forgets its improvements, Undo and all.
            improvementFailure = nil
            if typedState == nil { forgetContextImprovements() }
        }
    }
    /// The decisions the Context card makes as you type, in Decision mode, while its Live switch is on (see
    /// `LiveDecisions`); `refreshLiveDecisions()` tells it what to ask.
    let liveDecisions: LiveDecisions
    /// Whether Improve's request is on its way (see `improveContext()`).
    private(set) var isImprovingContext = false
    /// What Improve edited on the Context card, oldest first, for Undo while the improved text stands.
    private(set) var contextImprovements: [ImprovedContext] = []
    /// Why the last Improve brought nothing, until the text changes.
    private(set) var improvementFailure: String?
    @ObservationIgnored private var improvementTask: Task<Void, Never>?
    /// The scope the switch under the input was last set to in this chat, for the note that says what it decides
    /// about (see `DecisionScopeNote`): set by a click on the switch (`chooseScope(_:)`), the whole text too when
    /// it was switched back to, and nil until then, once the question goes, and in a new chat, so the note never
    /// shows by itself.
    var explainedScope: DecisionScope?
    /// The images and files the last Finder selection brought (see `bring(files:)`), which the next one replaces.
    @ObservationIgnored private var broughtAttachments: Set<UUID> = []
    private(set) var turns: [Turn] = []
    private(set) var history: [PastChat] = [] {
        didSet { scheduleExpiry() }
    }
    /// When the open chat's time runs out, while it has one (see `expiresAt`).
    private var deadline = Date.distantFuture {
        didSet { scheduleExpiry() }
    }
    private(set) var mode = Mode.chat
    /// The folder an agent works in for this chat, made on the first question to one.
    private(set) var workspace: ChatWorkspace?
    private(set) var isStreaming = false
    private(set) var failure: String? {
        didSet { if failure == nil { failureRetry = nil } }
    }
    private(set) var failureNeedsSettings = false
    /// What Try Again on the failure's banner does, when the failure is one asking again might mend: ask the
    /// question again for the answer that was cut short, or send the question that came back to the input.
    enum FailureRetry: Equatable {
        case askAgain
        case send
        /// Ask every preset again, the round that brought no answer (see `askPresets(_:)`).
        case askPresets(PresetDecisions)
    }
    private(set) var failureRetry: FailureRetry?
    /// A friendly line from a game: its invitation, why a move came back, or that the round is over.
    /// Unlike `failure`, nothing went wrong.
    private(set) var nudge: String?
    /// Two or three questions to ask next, suggested on this Mac under the last answer (see `FollowUps`). In memory
    /// only and in no turn, so Recent Chats never keeps them; every request clears them, and a reopened chat gets
    /// new ones.
    private(set) var followUps: [String] = []
    /// Whether the follow-ups for the last answer are still being worked out, for the capsule that says so. It turns
    /// on only once they have taken `FollowUps.loadingDelay`, so the ones drawn from the answer at once never flash it.
    private(set) var isSuggestingFollowUps = false
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
    /// Streamed text that hasn't joined the streaming turn's answer yet, and the task that adds it once
    /// `textInterval` is up (see `hold(_:)`).
    @ObservationIgnored private var heldText = ""
    @ObservationIgnored private var heldTextTask: Task<Void, Never>?
    /// How long streamed text waits at most; `textInterval`, and their own in tests.
    @ObservationIgnored var textInterval = ChatSession.textInterval
    /// The game move that came back last; sending it again unchanged insists on it.
    @ObservationIgnored private var insistedInput: String?
    /// The answer Ask Again is replacing, which comes back if the new one brings no text.
    @ObservationIgnored private var replacedTurn: Turn?
    /// Whether the answer streaming now rewrites `replacedTurn`, which then comes back unless it finishes.
    @ObservationIgnored private var isRewriting = false
    /// The answers that rewrites and presets replaced, most recent last, each with the turn that took its place,
    /// so Undo Rewrite can bring it back while that turn is still the last (see `undoRewrite()`). In memory with
    /// the chat, and gone with it.
    @ObservationIgnored private var rewritten: [(before: Turn, after: Turn.ID)] = []
    /// How to answer each prompt the agent is waiting on, by the prompt's id.
    @ObservationIgnored private var responders: [String: AgentPromptResponder] = [:]
    /// Lets go of the chats whose time is up, at the next deadline.
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    /// Working out what the last answer changed in the text its question was about, for tests to wait on.
    @ObservationIgnored private(set) var changesSearch: Task<Void, Never>?
    /// The chat's workspace was gone and was made again, for the next question to say so.
    @ObservationIgnored private var remadeWorkspace = false
    /// The most memory the chat may take; `chatByteLimit`, lower in tests.
    @ObservationIgnored var byteLimit = ChatSession.chatByteLimit
    /// What the games draw with before a move goes to the model; seeded in tests.
    @ObservationIgnored var dice = GameDice()
    /// Works out the follow-ups for an answer; tests pass their own.
    @ObservationIgnored var followUpSuggester: (FollowUps.Request) async -> [String] = FollowUps.suggest
    @ObservationIgnored private var followUpTask: Task<Void, Never>?
    @ObservationIgnored private var followUpLoadingTask: Task<Void, Never>?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let workspaceRoot: URL
    @ObservationIgnored private let streamReplies: @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error>
    /// The count of how Meraline is used: questions, answers, tokens, games, never their words (see `UsageLedger`).
    @ObservationIgnored let usage: UsageLedger

    /// `stream` talks to the provider, and `decideLive` asks the live decisions on the Context card; tests pass
    /// ones that reply on their own, and their own `workspaceRoot` so they never touch the app's workspaces.
    /// `stream` comes first so a trailing closure is still it.
    init(
        preferences: Preferences,
        workspaceRoot: URL = ChatWorkspace.defaultRoot,
        usage: UsageLedger = .shared,
        stream: @escaping @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> = LLMClient.stream,
        decideLive: @escaping LiveDecisions.Decide = DecisionClient.decide
    ) {
        self.preferences = preferences
        self.workspaceRoot = workspaceRoot
        self.usage = usage
        liveDecisions = LiveDecisions(preferences: preferences, usage: usage, decide: decideLive)
        streamReplies = stream
    }

    var canSend: Bool {
        guard !isStreaming else { return false }
        guard let gameState else {
            guard fileNotice == nil, pictureNotice == nil, bulkNotice == nil else { return false }
            // A decision takes a question; context sharpens it but is optional.
            if isDeciding { return !draft.trimmed.isEmpty }
            return !draft.trimmed.isEmpty || !draftImages.isEmpty || !draftFiles.isEmpty || !draftSelections.isEmpty
        }
        switch gameState.phase {
        case .modelMoves, .opening, .over: return true
        case .yourMove: return !draft.trimmed.isEmpty
        case .waiting: return false
        }
    }

    /// The game being played, or nil in an ordinary chat.
    var game: Game? {
        if case .game(let game) = mode { game } else { nil }
    }

    var isPlaying: Bool { game != nil }

    /// When the open chat goes, workspace and all, for the timer under the card. Nil while there is no chat, and
    /// while a game waits for its first move, which starts its time.
    var expiresAt: Date? {
        (turns.isEmpty && !isPlaying) || deadline == .distantFuture ? nil : deadline
    }

    /// Where the game stands, worked out from the turns by its rules.
    var gameState: GameState? { game?.rules.state(of: turns) }

    /// The game is waiting for you.
    var isYourMove: Bool { !isStreaming && gameState?.isYourMove == true }

    /// The game has a hint for your move.
    var canHint: Bool { isYourMove && gameState?.hints.isEmpty == false }

    var lastAnswer: String? {
        turns.last(where: { !$0.answer.isEmpty })?.answer
    }

    /// The kind of model the last answer came from, for the count of what is done with it: the mode's when no
    /// model gave it, as with a game's move drawn on this Mac.
    var lastAnswerKind: ProviderKind {
        turns.last(where: { !$0.answer.isEmpty })?.provider?.kind ?? preferences.mode
    }

    /// The kind of model the draft goes to, for the count of what is added to it.
    var askingKind: ProviderKind { preferences.mode }

    /// The files an agent handed over last in this chat, for the chat's actions.
    var lastPresentedFiles: [PresentedFile] {
        turns.last(where: { !$0.presentedFiles.isEmpty })?.presentedFiles ?? []
    }

    /// Why the draft waits: it has files, which only an agent reads, and the panel is asking an LLM or for a
    /// decision. Switching to Agent sends them as they are.
    var fileNotice: String? {
        guard preferences.mode != .agent, !draftFiles.isEmpty else { return nil }
        let kinds = FileAttachment.kinds(of: draftFiles)
        return "Only an agent can read \(kinds). Switch to Agent to send \(draftFiles.count == 1 ? "it" : "them")."
    }

    /// Why the draft waits: it has pictures, which a decision model can't read. Switching to LLM sends them as
    /// they are.
    var pictureNotice: String? {
        guard isDeciding, !draftImages.isEmpty else { return nil }
        let one = draftImages.count == 1
        return "A decision reads text only, not \(one ? "a picture" : "pictures"). Switch to LLM to ask about \(one ? "it" : "them")."
    }

    /// Why the draft waits: the question is about each word or line, and the texts have more of them than one
    /// question decides about (see `DecisionScope.itemLimit`). Deciding about the whole text sends it as it is.
    var bulkNotice: String? {
        let scope = preferences.decisionScope
        guard isDeciding, scope != .whole else { return nil }
        let count = scope.items(in: decisionState).count
        guard count > DecisionScope.itemLimit else { return nil }
        return "A decision about each \(scope.noun) takes up to \(DecisionScope.itemLimit.formatted()) \(scope.noun)s, and the text has \(count.formatted()). Decide about the whole text instead, or about less of it."
    }

    /// Whether the next question asks for a decision: Decision mode, in a chat rather than a game.
    var isDeciding: Bool { preferences.mode == .decision && !isPlaying }

    /// What a decision is about: the texts of the chat so far and those waiting in the draft, the written one
    /// included (see `DecisionRequest`). Context is optional, but a follow-up asks about the same texts the chat kept.
    var decisionState: [SelectedText] {
        turns.flatMap(\.selections) + draftSelections + (typedSelection.map { [$0] } ?? [])
    }

    var hasDecisionState: Bool { !decisionState.isEmpty }

    /// Whether a decision has no context yet, for the row beside the input that suggests adding some (it is
    /// optional). The card for writing it stands in the row's place, so the row goes as soon as the card opens.
    var needsDecisionState: Bool { isDeciding && !hasDecisionState && typedState == nil }

    /// The text written in the window as a text of its own, or nil while there is none.
    var typedSelection: SelectedText? { typedState.flatMap(SelectedText.typed) }

    /// Opens the card for writing a note to send with the question (`TypedStateCard`): Tab in any mode, or
    /// Decision's Write It row. In Decision it is the text to decide about; in LLM and Agent modes it is a piece
    /// of context of its own, sent as `SelectedText.typed`.
    func writeState() {
        guard !isPlaying, typedState == nil else { return }
        typedState = ""
    }

    func removeTypedState() {
        typedState = nil
    }

    /// Tab from the card: an empty card goes, so Tab closes what Tab opened, and one with text stays; the input
    /// takes the keyboard either way (see `PanelController`).
    func leaveTypedState() {
        guard let typedState, typedState.trimmed.isEmpty else { return }
        self.typedState = nil
    }

    /// Whether a question ends in a colon ("Fix the grammar:"), which says the text comes next.
    nonisolated static func endsInColon(_ draft: String) -> Bool {
        draft.trimmed.hasSuffix(":")
    }

    /// Whether the draft holds nothing for a question to work on: no text, file, or picture. A preset put in
    /// then, or a colon typed at the end of the question, opens the card for writing the text.
    var hasNothingToWorkOn: Bool { draftSelections.isEmpty && draftFiles.isEmpty && draftImages.isEmpty }

    /// Whether the draft holds no context at all: nothing to work on, and no text on the Context card either. A
    /// click on a preset then puts it in the input instead of asking it (see `apply(_:among:)`).
    var hasNoContext: Bool { hasNothingToWorkOn && typedState?.trimmed.isEmpty != false }

    /// Opens the card as the question comes to end in a colon, in LLM and Agent modes (a decision's colon names
    /// its answers), with nothing in the draft to work on. The keyboard stays in the input, where the colon was
    /// just typed; Tab moves to the card. Only the colon's arrival opens it, so a card closed by its cross stays
    /// closed while the colon stays.
    private func writeStateAfterColon() {
        guard preferences.mode != .decision, !isStreaming, hasNothingToWorkOn else { return }
        writeState()
    }

    /// A click on the scope switch under the input (`DecisionScopeToggle`): the scope is kept in Settings, and
    /// the note under the input says what it decides about until the question goes or the chat does.
    func chooseScope(_ scope: DecisionScope) {
        preferences.decisionScope = scope
        explainedScope = scope
    }

    // MARK: Live decisions

    /// What the Context card decides live right now (see `LiveDecisions`): the chat's texts and the draft's, the
    /// question in the input and the presets turned on (`liveQuestions`), for the decision provider in use. Nil,
    /// which shows nothing, while the Live switch is off, outside Decision mode, while the card is closed, and
    /// while an answer comes.
    var liveAsk: LiveDecisions.Ask? {
        guard liveDecisions.isOn, isDeciding, typedState != nil, !isStreaming,
              let provider = preferences.activeProvider, provider.kind == .decision else { return nil }
        return LiveDecisions.Ask(state: decisionState, questions: liveQuestions, provider: provider, settings: preferences[provider])
    }

    /// The questions the Context card decides live: those kept from the input (`LiveDecisions.keptQuestions`),
    /// then the input's, when there is one, so keeping it leaves its capsule where it is and moves no other, then
    /// Decision's presets in their order, each on or off (`LiveDecisions.enabledPresets`).
    var liveQuestions: [LiveQuestion] {
        let fallback = defaultAnswers
        let on = liveDecisions.enabledPresets
        let kept = liveDecisions.keptQuestions.compactMap { LiveQuestion.kept($0, fallback: fallback) }
        let input = LiveQuestion.input(draft, fallback: fallback).map { [$0] } ?? []
        return kept + input + preferences[presets: .decision].compactMap { LiveQuestion.preset($0, isOn: on.contains($0.id), fallback: fallback) }
    }

    /// Tells the live decisions what to ask, after a change of the text, the question, the mode, or the provider;
    /// `atOnce` skips the pause typing gets, for a click.
    func refreshLiveDecisions(atOnce: Bool = false) {
        liveDecisions.update(liveAsk, atOnce: atOnce)
    }

    /// The Live switch on the Context card: the card starts deciding as you type, or stops, with no preset on and
    /// no kept question either way; the input's question is asked as it is.
    func toggleLiveDecisions() {
        liveDecisions.toggle()
        Log.chat.info("Live decisions turned \(liveDecisions.isOn ? "on" : "off")")
        refreshLiveDecisions(atOnce: true)
    }

    /// A click on a preset's capsule under the Context card's text: the preset is asked with the others from now
    /// on, or no longer.
    func toggleLivePreset(_ id: PromptPreset.ID) {
        liveDecisions.togglePreset(id)
        refreshLiveDecisions(atOnce: true)
    }

    /// The plus on the input's capsule under the Context card's text: the question in the input is kept as a
    /// question of its own (`KeptQuestion`), asked beside the presets with the answer it has, and the input
    /// empties for the next one.
    func keepLiveQuestion() {
        let text = draft.trimmed
        guard !text.isEmpty else { return }
        liveDecisions.keep(text)
        draft = ""
        refreshLiveDecisions(atOnce: true)
    }

    /// A click on a kept question's capsule: it is asked from now on, or no longer.
    func toggleLiveQuestion(_ id: UUID) {
        liveDecisions.toggleKept(id)
        refreshLiveDecisions(atOnce: true)
    }

    /// The cross on a kept question's capsule.
    func removeLiveQuestion(_ id: UUID) {
        liveDecisions.removeKept(id)
        refreshLiveDecisions(atOnce: true)
    }

    // MARK: Improving the context

    /// The text the Context card held before Improve edited it, what it became, and the edits in numbers (see
    /// `improveContext()`), kept with the open chat for Undo while the improved text stands.
    struct ImprovedContext: Equatable {
        let before: String
        let after: String
        let changes: TextChanges?
        /// How much the model was allowed to change (see `ContextImprovement.Stage`).
        let stage: ContextImprovement.Stage
        /// The answers it was asked with, about `before`, for `nextImprovementStage`.
        let answers: [LiveQuestion.ID: Decision]
    }

    /// The provider Improve edits with: the LLMs' default, or the agents', since a decision model writes nothing.
    var improvementProvider: Provider? {
        preferences.defaultProvider(for: .llm) ?? preferences.defaultProvider(for: .agent)
    }

    /// Whether Improve can take the Context card's text: the card decides live (`liveAsk`), there is text on it,
    /// a question is on to improve toward, an LLM is ready to edit, and no improvement is on its way.
    var canImproveContext: Bool {
        guard let ask = liveAsk, !isImprovingContext, improvementProvider != nil else { return false }
        return ask.questions.contains(where: \.isOn) && typedState?.trimmed.isEmpty == false
    }

    /// The stage the next click on Improve starts at (see `ContextImprovement.nextStage`): small edits, unless the
    /// last improvement still stands and the live decisions about its text show it didn't make the answers surer,
    /// which takes the next stage, up to the whole text; the stage it landed at again while it is helping, and
    /// small edits once every answer is what it should be.
    var nextImprovementStage: ContextImprovement.Stage {
        guard canUndoContextImprovement, let last = contextImprovements.last, let ask = liveAsk else { return .edit }
        return ContextImprovement.nextStage(after: last.stage, questions: ask.questions.filter(\.isOn), before: last.answers, after: liveDecisions.settledAnswers)
    }

    /// Improve on the Context card: the LLM reads the text, the questions on with the answers they have, and the
    /// answer each should get (`ContextImprovement.goal(of:answered:)`), and changes the text toward them as much
    /// as the click's stage allows (`ContextImprovement.improve`, from `nextImprovementStage`): small edits first,
    /// and in the same click the next stage while the text comes back as it was, so only a text that even a whole
    /// rewrite gives back as it was is left with a note. The changed text takes the card's, which asks the live
    /// decisions again at once, and the text before it waits for Undo (`undoContextImprovement()`). A text edited
    /// by hand meanwhile is left as it is, with a note under the capsules.
    func improveContext() {
        guard canImproveContext, let ask = liveAsk, let before = typedState, let provider = improvementProvider else { return }
        let questions = ask.questions.filter(\.isOn)
        let answers = liveDecisions.settledAnswers
        let stage = nextImprovementStage
        let others = ask.state.filter { !$0.isTyped }
        let settings = preferences[provider]
        let instructions = preferences.instructions(for: .improvement)
        isImprovingContext = true
        improvementFailure = nil
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))) to improve the Context card's text toward \(questions.count) question(s), from \(stage)")
        improvementTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await ContextImprovement.improve(
                    before, beside: others, toward: questions, answered: answers, from: stage,
                    provider: provider, settings: settings, instructions: instructions, stream: streamReplies
                )
                guard !Task.isCancelled else { return }
                // The button spins until the text lands, or is found changed meanwhile: the changes are worked
                // out off the main actor first, and a click, or a test, that took the reply for landed meanwhile
                // ran ahead of it.
                defer { isImprovingContext = false }
                count(reply, improving: before, toward: questions, others: others, with: provider)
                guard liveDecisions.isOn, let text = typedState else { return }
                guard text == before else {
                    improvementFailure = "The text changed meanwhile, so it was left as it is."
                    return
                }
                guard reply.text != before.trimmed else {
                    improvementFailure = "\(provider.name) left the text as it is, even asked to rewrite it whole."
                    Log.chat.info("The Context card's text came back as it was, through \(reply.requests) request(s)")
                    return
                }
                let changes = await Task.detached(priority: .userInitiated) { TextChanges.find(in: reply.text, against: [before]) }.value
                guard !Task.isCancelled, typedState == before else { return }
                contextImprovements.append(ImprovedContext(before: before, after: reply.text, changes: changes, stage: reply.stage, answers: answers))
                typedState = reply.text
                refreshLiveDecisions(atOnce: true)
                Log.chat.info("The Context card's text was improved at \(reply.stage), \(changes.map { "\($0.count) edit(s)" } ?? "largely")")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isImprovingContext = false
                improvementFailure = error.localizedDescription
                Log.chat.error("Improving the Context card's text failed: \(error.localizedDescription)")
            }
        }
    }

    /// Whether Undo can put back the text Improve edited: the improved text still stands on the card. Another
    /// undo takes back the improvement before it.
    var canUndoContextImprovement: Bool {
        guard let last = contextImprovements.last else { return false }
        return typedState == last.after
    }

    /// Puts back the text the last improvement edited, which asks the live decisions about it again at once.
    func undoContextImprovement() {
        guard canUndoContextImprovement, let undone = contextImprovements.popLast() else { return }
        typedState = undone.before
        refreshLiveDecisions(atOnce: true)
        Log.chat.info("The Context card's improvement was undone")
    }

    /// The note under the capsules: why the last Improve brought nothing, until the text changes, or else what the
    /// last improvement did, by its stage, and in numbers, while its text stands: “Improved: 5% changed · 2 edits”,
    /// “Rewrote parts: 38% changed · 9 edits”; a reply that kept too little of the text for numbers (see
    /// `TextChanges.minimumSimilarity`) says so, which is the whole text rewritten at its stage.
    var improvementNote: String? {
        if let improvementFailure { return improvementFailure }
        guard canUndoContextImprovement, let last = contextImprovements.last else { return nil }
        if let changes = last.changes { return "\(last.stage.done): \(changes.stats)" }
        return last.stage == .whole ? "Rewrote the whole text" : "\(last.stage.done): most of the text changed"
    }


    /// The card closed: an improvement on its way is dropped, and there is nothing to undo.
    private func forgetContextImprovements() {
        improvementTask?.cancel()
        improvementTask = nil
        isImprovingContext = false
        contextImprovements = []
        improvementFailure = nil
    }

    /// Counts an improvement in the ledger, under the LLM that edited: the click and what its requests took,
    /// estimated from what went and came when the provider reports no tokens.
    private func count(_ reply: ContextImprovement.Reply, improving text: String, toward questions: [LiveQuestion], others: [SelectedText], with provider: Provider) {
        let model = reply.usage?.model ?? preferences[provider].model
        let key = UsageTally.ModelTally.key(provider: provider, model: model)
        let price = usage.price(for: provider, model: model)
        let reported = reply.usage?.hasTokens == true
        var took = reply.usage ?? TokenUsage()
        if !reported {
            took.input = UsageTally.estimatedTokens(in: ContextImprovement.question(text: text, others: others, questions: questions, answers: [:])) * reply.requests
            took.output = UsageTally.estimatedTokens(in: reply.text)
        }
        usage.record(as: provider.kind) { tally in
            tally.contextImprovements += 1
            tally.providers[provider.rawValue, default: 0] += 1
            if provider.isCommandLine { tally.agentRuns += 1 }
            tally.count(answer: took, reported: reported, for: key, price: price)
        }
    }


    /// The answers a question that names none picks from: Settings' answers, or Yes and No when they can't be
    /// read (see `DecisionAnswers`).
    var defaultAnswers: DecisionAnswers {
        DecisionAnswers.parse(preferences.decisionAnswers) ?? .yesNo
    }

    /// The answers the question in the input would pick from, for the capsule under the input.
    var draftAnswers: DecisionAnswers {
        DecisionAnswers.split(draft, fallback: defaultAnswers).answers
    }

    /// Whether the question in the input names its own answers after its question mark or colon (see
    /// `DecisionAnswers.split`), which the capsule under the input then shows in the default's place.
    var draftNamesAnswers: Bool {
        DecisionAnswers.split(draft, fallback: defaultAnswers).question != draft.trimmed
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
        let selections = draftSelections + (typedSelection.map { [$0] } ?? [])
        guard fits(Turn(question: question, images: images, selections: selections)) else { return }
        let request = provider.kind == .decision
            ? makeDecisionRequest(asking: question, about: selections, of: provider)
            : makeRequest(asking: SelectedText.message(question, about: selections), images: images, files: files, of: provider)

        draft = ""
        draftImages = []
        draftFiles = []
        draftSelections = []
        typedState = nil
        explainedScope = nil
        failure = nil
        var turn = Turn(question: question, images: images, files: files, selections: selections)
        turn.provider = provider
        turn.estimatedInput = Self.estimatedTokens(in: request)
        turns.append(turn)
        isStreaming = true
        let isFirst = turns.count == 1
        usage.record(as: provider.kind) { tally in
            tally.questions += 1
            if isFirst { tally.chats += 1 }
            tally.wordsAsked += UsageTally.words(in: question)
            tally.providers[provider.rawValue, default: 0] += 1
            if provider.isCommandLine { tally.agentRuns += 1 }
            tally.images += images.count
            tally.files += files.filter { !$0.isFolder }.count
            tally.folders += files.filter(\.isFolder).count
            tally.selections += selections.filter { !$0.isFromClipboard }.count
            tally.clipboards += selections.filter(\.isFromClipboard).count
        }
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))), turn \(turns.count), \(images.count) image(s), \(files.count) file(s), \(selections.count) text(s)")
        stream(request, for: turn.id)
    }

    // MARK: Every preset at once

    /// Whether the circle at the end of Decision's presets can ask them now (see `askPresets(_:)`): an empty chat,
    /// where the presets are, in Decision mode with a decision model ready, no answer coming, text to decide
    /// about, no picture or file waiting on a switch of mode, and a preset with a question.
    func canAskPresets(among presets: [PromptPreset]) -> Bool {
        canAsk(PresetDecisions(presets: presets, fallback: defaultAnswers))
    }

    private func canAsk(_ round: PresetDecisions) -> Bool {
        turns.isEmpty && isDeciding && !isStreaming && hasDecisionState && fileNotice == nil && pictureNotice == nil
            && preferences.activeProvider?.kind == .decision && !round.isEmpty
    }

    /// The circle at the end of Decision's presets (see `PromptPresets`): every preset with a question is asked at
    /// once about the chat's texts and the draft's, in one turn, whose question is the presets' titles, and one
    /// request carrying every question (see `PresetDecisions`, `makePresetsRequest(_:about:of:)`), each answer on
    /// the card as it comes. The texts go with the turn as a question's do; whatever is typed in the input stays
    /// there, for a follow-up about the same texts.
    func askPresets(_ presets: [PromptPreset]) {
        ask(PresetDecisions(presets: presets, fallback: defaultAnswers))
    }

    private func ask(_ round: PresetDecisions) {
        guard canAsk(round), let provider = preferences.activeProvider else { return }
        let selections = draftSelections + (typedSelection.map { [$0] } ?? [])
        guard fits(Turn(question: round.headline, images: [], selections: selections)) else { return }
        let request = makePresetsRequest(round, about: selections, of: provider)
        draftSelections = []
        typedState = nil
        explainedScope = nil
        failure = nil
        var turn = Turn(question: round.headline, images: [], selections: selections)
        turn.presetDecisions = round
        turn.provider = provider
        turn.estimatedInput = Self.estimatedTokens(in: request)
        turns.append(turn)
        isStreaming = true
        let isFirst = turns.count == 1
        usage.record(as: provider.kind) { tally in
            tally.questions += 1
            if isFirst { tally.chats += 1 }
            tally.providers[provider.rawValue, default: 0] += 1
            tally.selections += selections.filter { !$0.isFromClipboard }.count
            tally.clipboards += selections.filter(\.isFromClipboard).count
        }
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))) every preset, \(round.questions.count) question(s), turn \(turns.count), \(selections.count) text(s)")
        stream(request, for: turn.id)
    }

    /// The request Decision's presets make at once (see `PresetDecisions`): the chat's texts so far and
    /// `selections` as the state, as `makeDecisionRequest` has them, and every question of the round.
    func makePresetsRequest(_ round: PresetDecisions, about selections: [SelectedText], of provider: Provider) -> ChatRequest {
        var request = makeRequest(asking: SelectedText.message(round.headline, about: selections), images: [], of: provider)
        let context = turns.filter(\.isComplete).flatMap(\.selections) + selections
        request.decision = DecisionRequest(state: context, question: round.headline, answers: .yesNo, presets: round)
        return request
    }

    /// Gets the provider in use ready for the next question, as the window opens or the mode or provider changes:
    /// Apple's model loads, and Claude Code or Codex starts in the chat's workspace (see `LiveAgents`). Nothing
    /// starts while an answer streams, or in the test host.
    func prewarm() {
        guard !MeralineApp.isHostingTests, let provider = preferences.activeProvider else { return }
        if provider.isOnDevice { AppleIntelligenceClient.prewarm() }
        guard LiveAgents.handles(provider), !isStreaming else { return }
        // The last message stands for the question to come, so the agent can tell whether it follows on.
        LiveAgents.shared.prewarm(makeRequest(asking: "…", images: [], of: provider))
    }

    /// Whether Ask Again can ask the last question once more: a chat, not a game, whose last answer is done; a
    /// round of presets only of a decision model.
    var canAskAgain: Bool {
        guard !isStreaming, !isPlaying, turns.last?.isComplete == true, let provider = preferences.activeProvider else { return false }
        return turns.last?.presetDecisions == nil || provider.kind == .decision
    }

    /// Whether the failure on the banner is one asking again might mend, which Try Again does: not a game's,
    /// nor a setup problem, which Open Settings is for.
    var canTryAgain: Bool {
        guard let failureRetry, !failureNeedsSettings, !isStreaming, !isPlaying else { return false }
        switch failureRetry {
        case .askAgain: return canAskAgain
        case .send: return !draft.trimmed.isEmpty
        case .askPresets(let round): return canAsk(round)
        }
    }

    /// Try Again on the failure's banner: asks the question again when its answer is on screen, cut short, and
    /// sends the question again as Return would when it came back to the input.
    func tryAgain() {
        guard canTryAgain, let failureRetry else { return }
        switch failureRetry {
        case .askAgain: askAgain()
        case .send: send()
        case .askPresets(let round): ask(round)
        }
    }

    /// Asks the last question again, of the provider in use now, for an answer in place of the last one.
    /// Whatever is typed in the input stays there.
    func askAgain() {
        guard canAskAgain, let provider = preferences.activeProvider, let last = turns.popLast() else { return }
        replacedTurn = last
        isRewriting = false
        // A round of presets is asked again whole, about the same texts.
        let round = last.presetDecisions?.cleared
        let request: ChatRequest
        if let round {
            request = makePresetsRequest(round, about: last.selections, of: provider)
        } else if provider.kind == .decision {
            request = makeDecisionRequest(asking: last.question, about: last.selections, of: provider)
        } else {
            request = makeRequest(asking: SelectedText.message(last.question, about: last.selections), images: last.images, files: last.files, of: provider)
        }
        failure = nil
        var turn = Turn(question: last.question, images: last.images, files: last.files, selections: last.selections)
        turn.presetDecisions = round
        turn.provider = provider
        turn.estimatedInput = Self.estimatedTokens(in: request)
        turns.append(turn)
        isStreaming = true
        usage.record(as: provider.kind) { tally in
            tally.askAgains += 1
            tally.providers[provider.rawValue, default: 0] += 1
            if provider.isCommandLine { tally.agentRuns += 1 }
        }
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))) again, turn \(turns.count)")
        stream(request, for: turn.id)
    }

    /// Whether the last answer can be told again another way: as for Ask Again, with text to rewrite, which a
    /// decision isn't.
    var canRewrite: Bool {
        canAskAgain && turns.last?.answer.trimmed.isEmpty == false && turns.last?.isDecision != true
    }

    /// Tells the last answer again another way, asking the provider in use now. The model reads the
    /// conversation with the old answer in it, and the new answer takes that one's place under the same
    /// question, keeping the tools it used and the asks it settled, so a follow-up or the next rewrite reads
    /// the new one. Whatever is typed in the input stays there.
    func rewrite(_ rewrite: Rewrite) {
        rewriteLastAnswer(asking: rewrite.instruction, countedAs: rewrite.rawValue, named: rewrite.rawValue)
    }

    /// A rewrite of the last answer that `instruction` asks for, never shown, counted in the usage ledger under
    /// `key`, a name of Meraline's own and never text of yours, and logged as `name`: a `Rewrite`, or a preset
    /// run on the answer (see `run(_:)`).
    func rewriteLastAnswer(asking instruction: String, countedAs key: String, named name: String) {
        guard canRewrite, let provider = preferences.activeProvider else { return }
        let request = makeRequest(asking: instruction, images: [], of: provider)
        guard let last = turns.popLast() else { return }
        replacedTurn = last
        isRewriting = true
        failure = nil
        var turn = Turn(question: last.question, images: last.images, files: last.files, selections: last.selections)
        turn.tools = last.tools
        turn.prompts = last.prompts
        turn.presentedFiles = last.presentedFiles
        turn.provider = provider
        turn.estimatedInput = Self.estimatedTokens(in: request)
        turns.append(turn)
        isStreaming = true
        usage.record(as: provider.kind) { tally in
            tally.rewrites[key, default: 0] += 1
            tally.providers[provider.rawValue, default: 0] += 1
            if provider.isCommandLine { tally.agentRuns += 1 }
        }
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))) to rewrite the last answer (\(name)), turn \(turns.count)")
        stream(request, for: turn.id)
    }

    /// Whether the last answer came from a rewrite or a preset that Undo Rewrite can take back: the answer it
    /// replaced is kept while that one is the last, and nothing is streaming.
    var canUndoRewrite: Bool {
        guard !isStreaming, let last = turns.last, let replaced = rewritten.last else { return false }
        return replaced.after == last.id
    }

    /// Puts back the answer the last rewrite or preset replaced, with what it carried, under the same question,
    /// so a ⌘1 pressed by habit, or a rewrite that came out worse, costs nothing. Another undo takes back the
    /// rewrite before it. Whatever is typed in the input stays there.
    func undoRewrite() {
        guard canUndoRewrite, let undone = rewritten.popLast() else { return }
        turns[turns.count - 1] = undone.before
        failure = nil
        suggestFollowUps(after: undone.before)
        Log.chat.info("Rewrite undone; the answer it replaced is back")
    }

    /// What Return does in a game: asks the model for its move, opens a round with your line or leaves it to
    /// the other side when nothing is typed, or plays your line.
    private func play(_ game: Game) {
        switch game.rules.state(of: turns).phase {
        case .modelMoves(let cue):
            askModel(cue, in: game)
        case .opening(let opening), .over(_, let opening):
            let input = draft.trimmed
            guard opening.takesYourMove, !input.isEmpty else {
                open(game)
                return
            }
            insistedInput = nil
            make(game.rules.open(with: input, after: turns), from: input, in: game)
        case .waiting:
            break
        case .yourMove:
            let input = draft.trimmed
            let move = game.rules.play(input, in: turns, insisting: input == insistedInput)
            insistedInput = nil
            make(move, from: input, in: game)
        }
    }

    /// Carries out a move you typed as `input`.
    private func make(_ move: GameMove, from input: String, in game: Game) {
        if case .reject = move {
            usage.record(as: gameKind) { $0.games[game.rawValue, default: .init()].rejectedMoves += 1 }
        } else {
            usage.record(as: gameKind) { $0.games[game.rawValue, default: .init()].moves += 1 }
        }
        switch move {
        case .reject(let message):
            Log.chat.info("\(game.title): your move came back")
            nudge = message
            insistedInput = input
        case .ask(let line):
            ask(Turn(question: line, images: []), in: game)
        case .open(let line, let cue):
            ask(Turn(question: line, images: [], cue: cue), in: game)
        case .record(let line, let outcome):
            draft = ""
            failure = nil
            nudge = nil
            turns.append(Turn(question: line, images: [], isComplete: true, outcome: outcome))
            restartClock()
            Log.chat.info("\(game.title): your move kept, turn \(turns.count)")
            advance(game, asksModel: true)
        case .settle(let outcome):
            guard !turns.isEmpty else { return }
            draft = ""
            failure = nil
            nudge = nil
            turns[turns.count - 1].outcome = outcome
            restartClock()
            Log.chat.info("\(game.title): round settled, turn \(turns.count)")
            advance(game, asksModel: true)
        }
    }

    /// Sends your move to the model, which replies with its own.
    private func ask(_ move: Turn, in game: Game) {
        guard let provider = gameProvider else {
            fail(with: setupMessage(to: "play"), needsSettings: true)
            return
        }
        var turn = move
        turn.aside = game.rules.aside(for: turn, after: turns, in: preferences.language, dice: &dice)
        let request = makeRequest(asking: turn.message, images: [], of: provider)
        turn.provider = provider
        turn.estimatedInput = Self.estimatedTokens(in: request)
        draft = ""
        failure = nil
        nudge = nil
        turns.append(turn)
        isStreaming = true
        Log.chat.info("\(game.title): your move to \(provider.name) (\(modelName(for: provider))), turn \(turns.count)")
        stream(request, for: turn.id)
    }

    /// Leaves the round's opening to the other side: the model, asked with a cue, or this Mac, with a move it
    /// drew and keeps as the model's. Anything typed stays in the input.
    private func open(_ game: Game) {
        switch game.rules.opener(after: turns, in: preferences.language, dice: &dice) {
        case .ask(let cue):
            askModel(cue, in: game)
        case .drawn(let cue, let move):
            failure = nil
            nudge = nil
            turns.append(Turn(question: "", images: [], answer: move, isComplete: true, cue: cue))
            restartClock()
            Log.chat.info("\(game.title): this Mac opened the round, turn \(turns.count)")
            advance(game, asksModel: true)
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
            let figures = game.figures(ofRoundEndingIn: turns)
            usage.record(as: gameKind) { $0.games[game.rawValue, default: .init()].count(round: outcome.youWon, with: figures) }
            nudge = outcome.text
        default:
            break
        }
    }

    /// Asks the model for a move of its own: a turn with a cue and nothing of yours. If that fails,
    /// Return asks again.
    private func askModel(_ cue: String, in game: Game) {
        guard let provider = gameProvider else {
            fail(with: setupMessage(to: "play"), needsSettings: true)
            return
        }
        var turn = Turn(question: "", images: [], cue: cue)
        turn.aside = game.rules.aside(for: turn, after: turns, in: preferences.language, dice: &dice)
        let request = makeRequest(asking: turn.message, images: [], of: provider)
        turn.provider = provider
        turn.estimatedInput = Self.estimatedTokens(in: request)
        failure = nil
        nudge = nil
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
        case .decision: "Add a TypeSafe or OpenRouter API key, or turn on Ollama, in Settings to \(goal), or switch to LLM."
        }
    }

    /// The provider a game plays against: the one in use, unless it is a decision model, which answers yes or no
    /// and nothing else; then the LLMs' default, or the agents'.
    private var gameProvider: Provider? {
        guard let provider = preferences.activeProvider, provider.kind != .decision else {
            return preferences.defaultProvider(for: .llm) ?? preferences.defaultProvider(for: .agent)
        }
        return provider
    }

    /// The kind of model a game is played against, for the count of usage.
    private var gameKind: ProviderKind { gameProvider?.kind ?? .llm }

    private func modelName(for provider: Provider) -> String {
        let model = preferences[provider].model.trimmed
        return model.isEmpty ? "default model" : model
    }

    /// How an answer ended, for the count of usage.
    private enum AnswerEnd {
        case complete, stopped, failed
    }

    /// Counts an answer that ended: how, what it took, and, in a chat, what it brought. A rewrite's turn keeps
    /// the old answer's tools and asks, so `tools` is false for it; a game's move counts only what it took.
    private func count(_ end: AnswerEnd, of turn: Turn, tools: Bool = true, inGame: Bool = false, now: Date = .now) {
        let provider = turn.provider ?? preferences.activeProvider ?? .custom
        let model = turn.usage?.model ?? preferences[provider].model
        let key = UsageTally.ModelTally.key(provider: provider, model: model)
        let price = usage.price(for: provider, model: model)
        let turnCount = turns.count
        // Every decision Jev made: one about the text, one a word or line, or one a preset.
        let decided = turn.presetDecisions?.decided ?? turn.decisions.map { $0.items.map(\.decision) } ?? turn.decision.map { [$0] } ?? []
        let unsure = decided.filter { $0.isUnsure(below: preferences.unsureBelow) }.count
        usage.record(at: now, as: provider.kind) { tally in
            switch end {
            case .failed:
                tally.failures += 1
                return
            case .stopped:
                tally.stops += 1
            case .complete:
                if !inGame { tally.answers += 1 }
                tally.decisions += decided.count
                tally.unsureDecisions += unsure
            }
            tally.secondsWaited += max(0, now.timeIntervalSince(turn.sentAt))
            tally.waits += 1
            let reported = turn.usage?.hasTokens == true
            var took = turn.usage ?? TokenUsage()
            if !reported {
                took.input = turn.estimatedInput
                took.output = UsageTally.estimatedTokens(in: turn.answer)
            }
            tally.count(answer: took, reported: reported, for: key, price: price)
            guard !inGame else { return }
            let words = UsageTally.words(in: turn.answer)
            tally.wordsRead += words
            tally.longestAnswer = max(tally.longestAnswer, words)
            tally.longestChat = max(tally.longestChat, turnCount)
            tally.filesHandedOver += turn.presentedFiles.count
            guard tools else { return }
            tally.toolUses += turn.tools.count
            tally.mcpUses += turn.tools.filter { if case .mcp = $0 { true } else { false } }.count
            for prompt in turn.prompts {
                switch prompt.resolution {
                case .allowed?: tally.asksAllowed += 1
                case .denied?, .declinedByAgent?: tally.asksDenied += 1
                case .answered?: tally.questionsAnswered += 1
                case nil: break
                }
            }
        }
    }

    /// Roughly how many tokens a request is, for a provider that reports none: its text at about four
    /// characters a token, and a thousand for each picture.
    nonisolated static func estimatedTokens(in request: ChatRequest) -> Int {
        UsageTally.estimatedTokens(in: request.systemPrompt)
            + request.messages.reduce(0) { $0 + UsageTally.estimatedTokens(in: $1.text) + $1.images.count * 1_000 }
    }

    private func stream(_ request: ChatRequest, for id: Turn.ID) {
        restartClock()
        clearFollowUps()
        if remadeWorkspace, let index = turns.firstIndex(where: { $0.id == id }) {
            remadeWorkspace = false
            turns[index].notice = Self.remadeWorkspaceNotice
        }
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

    /// The request a question or a game move makes, with the prompt Settings › Prompt has for the provider's
    /// mode and the line for the language. A game sends its own prompt instead, the cue of each move the model made on its own, and what was
    /// drawn for each move. Two messages in a row from one side, which a game can leave, are joined into one.
    func makeRequest(asking question: String, images: [ImageAttachment], files: [FileAttachment] = [], of provider: Provider) -> ChatRequest {
        var messages: [ChatMessage] = []
        func add(_ role: ChatMessage.Role, _ text: String, _ images: [ImageAttachment] = [], _ files: [FileAttachment] = [], presented: [String] = []) {
            guard !text.isEmpty || !images.isEmpty || !files.isEmpty else { return }
            if let previous = messages.last, previous.role == role {
                let joined = [previous.text, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                messages[messages.count - 1] = ChatMessage(
                    role: role,
                    text: joined,
                    images: previous.images + images,
                    files: previous.files + files,
                    presentedFiles: previous.presentedFiles + presented
                )
            } else {
                messages.append(ChatMessage(role: role, text: text, images: images, files: files, presentedFiles: presented))
            }
        }
        for turn in turns where turn.isComplete {
            add(.user, turn.message, turn.images, turn.files)
            add(.assistant, turn.answer, presented: turn.presentedFiles.map(\.path))
        }
        add(.user, question, images, files)
        return ChatRequest(
            provider: provider,
            settings: preferences[provider],
            // A decision model takes no prompt.
            systemPrompt: provider.kind == .decision ? "" : preferences.instructions(for: game.map(SystemPrompt.game) ?? .chat(provider.kind)),
            messages: messages,
            workspace: provider.isCommandLine ? workspaceForAgents()?.url : nil,
            presentsFiles: provider.isCommandLine && game == nil
        )
    }

    /// The request a question in Decision mode makes (see `DecisionRequest`): the chat's texts so far and
    /// `selections` as Jev's state, the question less the answers it names, and those answers, or Settings' when
    /// it names none, about the whole text or each of its words or lines (`Preferences.decisionScope`; a text
    /// with none of them is decided about whole). Jev keeps no conversation, so a follow-up asks about the same
    /// texts anew.
    func makeDecisionRequest(asking question: String, about selections: [SelectedText], of provider: Provider) -> ChatRequest {
        var request = makeRequest(asking: SelectedText.message(question, about: selections), images: [], of: provider)
        let split = DecisionAnswers.split(question, fallback: defaultAnswers)
        let context = turns.filter(\.isComplete).flatMap(\.selections) + selections
        let scope = preferences.decisionScope
        let items = scope.items(in: context)
        // Context is optional: with none, the question itself is what Jev decides about, so it always has a state.
        let state = context.isEmpty ? [SelectedText(split.question)].compactMap { $0 } : context
        request.decision = DecisionRequest(
            state: state,
            question: split.question,
            answers: split.answers,
            scope: items.isEmpty ? .whole : scope,
            items: items
        )
        return request
    }

    /// The chat's workspace, made on the first question to an agent, and again if it has gone missing.
    private func workspaceForAgents() -> ChatWorkspace? {
        if let workspace {
            if !workspace.exists { remake(workspace) }
            return workspace
        }
        do {
            workspace = try ChatWorkspace.make(in: workspaceRoot)
            Log.chat.info("Workspace made for this chat")
        } catch {
            Log.chat.error("Couldn’t make a workspace: \(error.localizedDescription)")
        }
        return workspace
    }

    static let remadeWorkspaceNotice = "This chat’s folder was gone, so Meraline made a new, empty one; macOS clears out old temporary files. The files from earlier questions, and what the agent kept there, are gone."

    /// macOS clears old files out of the temporary folder, so a chat kept long enough can find its workspace gone.
    /// It is made again, empty, and the agent carries on there, starting over from the transcript; the next
    /// question says what was lost. A game keeps nothing there, so it says nothing.
    private func remake(_ workspace: ChatWorkspace) {
        do {
            try workspace.remake()
            Log.chat.info("Workspace was gone and was made again")
        } catch {
            Log.chat.error("Couldn’t make the workspace again: \(error.localizedDescription)")
        }
        if !isPlaying { remadeWorkspace = true }
    }

    /// Whether a question fits in the chat's `byteLimit`. One that doesn't stays in the input, saying why.
    private func fits(_ turn: Turn) -> Bool {
        guard Self.byteCount(of: turns) + turn.byteCount > byteLimit else { return true }
        Log.chat.info("Question kept back: the chat is at its memory limit")
        fail(with: "This chat is full: it holds up to \(Int64(byteLimit).formatted(.byteCount(style: .memory))), mostly pictures. Take out an image, or start a new chat to keep asking.")
        return false
    }

    /// Roughly how much memory a chat's turns take.
    static func byteCount(of turns: [Turn]) -> Int {
        turns.reduce(0) { $0 + $1.byteCount }
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
    /// anonymous. While Live decisions are on, or the Context card holds text, the draft goes too (see
    /// `keptDraft`): with its chat, or in an empty one as a stash of its own, so Esc or ⌘N pressed by habit loses
    /// none of it. Says whether it was stashed.
    @discardableResult
    func reset(keepingChat: Bool = true) -> Bool {
        reset(keepingChat: keepingChat, draft: keepingChat ? keptDraft : nil)
    }

    /// Starts a new chat, `unsent` going to Recent Chats with the open one, or on its own when it has no answer to
    /// keep. Says whether it went on its own.
    private func reset(keepingChat: Bool, draft unsent: Draft?) -> Bool {
        // An answer cut short here goes to Recent Chats with every word that arrived.
        addHeldText()
        let stashed = archiveCurrentChat(keeping: keepingChat, draft: unsent)
        // The next chat's Context card starts with Live off and nothing on.
        liveDecisions.reset()
        streamTask?.cancel()
        streamTask = nil
        responders = [:]
        replacedTurn = nil
        isRewriting = false
        rewritten = []
        draft = ""
        draftImages = []
        draftFiles = []
        draftSelections = []
        typedState = nil
        explainedScope = nil
        turns = []
        mode = .chat
        isStreaming = false
        failure = nil
        failureNeedsSettings = false
        nudge = nil
        insistedInput = nil
        deadline = .distantFuture
        clearFollowUps()
        return stashed
    }

    /// What a new chat keeps of the open one's draft while Live decisions are on, or the Context card holds text,
    /// which is worth more than a line in the input: what is typed and added, the card's text, and the switch's
    /// questions and answers, which come back when it is reopened. Nil with neither, in a game, in anonymous mode,
    /// and while there is nothing in it.
    private var keptDraft: Draft? {
        guard !isPlaying, !isAnonymous, liveDecisions.isOn || typedState?.trimmed.isEmpty == false else { return nil }
        let draft = currentDraft
        return draft.isEmpty ? nil : draft
    }

    /// Whether a new chat would keep the draft (see `keptDraft`), for New Chat's words with no chat open.
    var keepsDraftOnReset: Bool { keptDraft != nil }

    /// Whether New Chat has something to clear with no chat open: the draft holds anything, the Context card's
    /// text included (see `PanelContext.newChat`).
    var canClearDraft: Bool {
        turns.isEmpty && !isPlaying && !currentDraft.isEmpty
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
        // A game is played against an LLM or an agent, never a decision model, so the toggle says which plays.
        if preferences.mode == .decision { preferences.mode = gameProvider?.kind ?? .llm }
        mode = .game(game)
        lastGame = game
        Log.chat.info("\(game.title) started")
        usage.record(as: gameKind) { $0.games[game.rawValue, default: .init()].started += 1 }
        advance(game, asksModel: true)
        nudge = game.rules.invitation
    }

    /// Starts the game being played over from its beginning. The game so far moves to Recent Chats, as when any
    /// game starts, and its finished rounds stay counted against the model.
    func restartGame() {
        guard let game else { return }
        Log.chat.info("\(game.title) restarted")
        startGame(game)
    }

    /// Plays one of a game's buttons, such as a word to pick, or the other side's opening.
    func choose(_ choice: String) {
        if let game, !isStreaming, case .opening(let opening)? = gameState?.phase, choice == opening.button {
            open(game)
            return
        }
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
        usage.record(as: gameKind) { $0.games[game.rawValue, default: .init()].hints += 1 }
    }

    /// What the rematch tray offers: the game's next round once one is over, or the last game again on an
    /// empty panel after it ended. How the round went is the transcript's last line, right above the tray, so the
    /// tray leads with the game's name rather than say it a second time; anything else there is to say, such as a
    /// move that broke the rules, still shows there.
    var rematch: RematchOffer? {
        if let game, !isStreaming, case .over(let outcome, _)? = gameState?.phase {
            let said = nudge.flatMap { $0 == outcome.text ? nil : $0 }
            return RematchOffer(game: game, message: said ?? game.title, versus: versus[game] ?? Versus(), isAfterGame: false)
        }
        guard !isPlaying, turns.isEmpty, let lastGame else { return nil }
        return RematchOffer(game: lastGame, message: lastGame.title, versus: versus[lastGame] ?? Versus(), isAfterGame: true)
    }

    /// Play Again in the rematch tray: the next round, opened by the other side as Return with nothing typed
    /// opens it, or the last game started over.
    func playAgain() {
        guard let rematch else { return }
        if rematch.isAfterGame {
            startGame(rematch.game)
        } else {
            open(rematch.game)
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

    /// Makes a past chat the open one, in the mode it was in, with the time it has left. Whatever was open moves
    /// to Recent Chats, a draft in an empty chat as a stash of its own. The chat leaves Recent Chats, so its
    /// workspace belongs to one chat only. A chat whose time is already up goes instead, workspace and all, and
    /// the open one stays. A draft kept with the chat comes back into the input; a stashed one has no time of its
    /// own, like anything typed.
    func reopen(_ chat: PastChat) {
        history.removeAll { $0.id == chat.id }
        guard chat.expiresAt > .now else {
            chat.workspace?.remove()
            Log.chat.info("A recent chat ran out of time as it was reopened")
            return
        }
        let typed = canStashDraft ? currentDraft : nil
        reset(keepingChat: true, draft: typed == nil ? keptDraft : nil)
        turns = chat.turns
        mode = chat.mode
        workspace = chat.workspace
        suggestFollowUps(after: turns.last)
        if !chat.isStash { deadline = chat.expiresAt }
        if let parked = chat.draft {
            restore(parked)
            Log.chat.info("A \(chat.isStash ? "stashed" : "chat's") draft is back in the input")
        }
        if case .game(let game) = mode { lastGame = game }
        if case .over(let outcome, _)? = gameState?.phase { nudge = outcome.text }
        if let typed { park(typed) }
    }

    /// Whether Stash Draft can park the draft in Recent Chats: something is in it, and no chat or game is open,
    /// since a follow-up belongs with its chat. Anonymous mode keeps drafts out of Recent Chats too.
    var canStashDraft: Bool {
        turns.isEmpty && !isPlaying && !isAnonymous && !currentDraft.isEmpty
    }

    /// Stash Draft (⌘S): parks what is typed and added in an empty chat in Recent Chats, where its time runs like
    /// any chat's there, and empties the input for something else. Reopening it puts it all back.
    func stashDraft() {
        guard canStashDraft else { return }
        let parked = currentDraft
        // What the last Finder selection brought leaves with the draft, so once it is back, the next selection
        // can't take it out again.
        broughtAttachments = []
        clearDraft()
        // Live's questions and answers left with the draft; the empty chat starts with Live off.
        liveDecisions.reset()
        park(parked)
        Log.chat.info("Draft stashed with \(parked.images.count) image(s), \(parked.files.count) file(s), \(parked.selections.count) text(s)")
    }

    private var currentDraft: Draft {
        Draft(text: draft, images: draftImages, files: draftFiles, selections: draftSelections, typedState: typedState, live: liveDecisions.snapshot)
    }

    /// Puts a draft back in the input: what was typed and added, the Context card's text, and, when Live was on,
    /// the switch with its questions and answers, in Decision mode, where they show.
    private func restore(_ parked: Draft) {
        if parked.live != nil { preferences.mode = .decision }
        (draft, draftImages, draftFiles, draftSelections, typedState) = (parked.text, parked.images, parked.files, parked.selections, parked.typedState)
        if let live = parked.live {
            liveDecisions.restore(live)
            refreshLiveDecisions(atOnce: true)
        }
    }

    /// Puts a draft on top of Recent Chats, letting go of the oldest chats past the limit.
    private func park(_ draft: Draft) {
        let previous = history
        history = Self.stashing(draft, into: history)
        removeWorkspaces(leftFrom: previous)
    }

    /// Moves the chat to Recent Chats with its workspace, the time it has left, and `draft`, unless the chat is
    /// anonymous or not `keeping`; a chat with no answer to keep leaves `draft` there as a stash of its own, which
    /// it says. A workspace whose chat is not kept is removed, as are those of the chats that drop off the end.
    /// Recent Chats keeps a chat until its time runs out, it is cleared or shaken away, or Meraline quits.
    private func archiveCurrentChat(keeping: Bool = true, draft: Draft? = nil) -> Bool {
        let previous = history
        var stashed = false
        if keeping && !isAnonymous {
            if turns.contains(where: Self.isKept) {
                let expiresAt = deadline == .distantFuture ? Date.now.addingTimeInterval(Self.chatLifetime) : deadline
                history = Self.archiving(turns, into: history, mode: mode, workspace: workspace, expiresAt: expiresAt, draft: draft)
            } else if let draft, !draft.isEmpty {
                history = Self.stashing(draft, into: history)
                stashed = true
            }
        }
        removeWorkspaces(leftFrom: previous)
        if let workspace, !history.contains(where: { $0.workspace == workspace }) { workspace.remove() }
        workspace = nil
        return stashed
    }

    /// Removes the workspaces of the chats in `previous` that are no longer in Recent Chats.
    private func removeWorkspaces(leftFrom previous: [PastChat]) {
        let kept = Set(history.map(\.id))
        for chat in previous where !kept.contains(chat.id) { chat.workspace?.remove() }
    }

    /// Recent Chats with the chat on top, holding at most `chatLimit` chats with the open one.
    static func archiving(_ turns: [Turn], into history: [PastChat], mode: Mode = .chat, at date: Date = .now, workspace: ChatWorkspace? = nil, expiresAt: Date? = nil, draft: Draft? = nil) -> [PastChat] {
        let answered = turns
            .filter(isKept)
            .map { turn in
                var turn = turn
                turn.activity = nil
                turn.prompts.removeAll(where: \.isPending)
                turn.isComplete = true
                return turn
            }
        guard !answered.isEmpty else { return history }
        let chat = PastChat(turns: answered, date: date, mode: mode, workspace: workspace, draft: draft, expiresAt: expiresAt ?? date.addingTimeInterval(chatLifetime))
        return Array(([chat] + history).prefix(chatLimit - 1))
    }

    /// Whether Recent Chats keeps a turn: it has an answer, or ended without one.
    private static func isKept(_ turn: Turn) -> Bool {
        !turn.answer.isEmpty || turn.isComplete
    }

    /// Recent Chats with a stashed draft on top, with 30 minutes of its own, holding at most `chatLimit` chats with
    /// the open one.
    static func stashing(_ draft: Draft, into history: [PastChat], at date: Date = .now) -> [PastChat] {
        guard !draft.isEmpty else { return history }
        let chat = PastChat(turns: [], date: date, draft: draft, expiresAt: date.addingTimeInterval(chatLifetime))
        return Array(([chat] + history).prefix(chatLimit - 1))
    }

    /// Forgets the recent chats, workspaces and all, and says how many went. The open chat stays.
    @discardableResult
    func forgetHistory() -> Int {
        dropShakenChats()
        let count = history.count
        for chat in history { chat.workspace?.remove() }
        history = []
        if count > 0 { Log.chat.info("\(count) recent chat(s) forgotten") }
        return count
    }

    /// How long a shake's forgetting can be taken back (see `shakeAwayHistory()`).
    static let shakeUndoWindow: Duration = .seconds(5)
    /// `shakeUndoWindow`, or a test's own.
    @ObservationIgnored var shakeUndoWindow = ChatSession.shakeUndoWindow
    /// The chats a shake forgot, held aside for `shakeUndoWindow` in case it was an accident, and the task that
    /// lets them go for good once it is up. Held, they count nowhere: not in the clock's count, nor the chats'
    /// limit, nor its panel. Nothing of them reaches disk that wasn't there: the workspaces stay until they go.
    @ObservationIgnored private var shakenChats: [PastChat] = []
    @ObservationIgnored private var shakenChatsTask: Task<Void, Never>?

    /// Whether a shake's forgetting can still be taken back.
    var canTakeBackShakenChats: Bool { !shakenChats.isEmpty }

    /// A shake of the window: the recent chats are forgotten, but held aside for `shakeUndoWindow` so the clock's
    /// capsule can offer Undo, since a shake asks nothing first. A shake inside that window lets the chats held
    /// before go for good. Says how many went.
    @discardableResult
    func shakeAwayHistory() -> Int {
        dropShakenChats()
        let count = history.count
        guard count > 0 else { return 0 }
        shakenChats = history
        history = []
        Log.chat.info("\(count) recent chat(s) forgotten by a shake, held for a moment")
        let window = shakeUndoWindow
        shakenChatsTask = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.dropShakenChats()
        }
        return count
    }

    /// Puts back the chats the last shake forgot, as they were: their order, the time each has left, their
    /// drafts and workspaces. One whose time ran out meanwhile stays gone, as it would have in Recent Chats.
    /// Says how many came back.
    @discardableResult
    func takeBackShakenChats(now: Date = .now) -> Int {
        shakenChatsTask?.cancel()
        shakenChatsTask = nil
        let held = shakenChats
        shakenChats = []
        guard !held.isEmpty else { return 0 }
        let expired = held.filter { $0.expiresAt <= now }
        for chat in expired { chat.workspace?.remove() }
        let kept = held.filter { $0.expiresAt > now }
        // Anything archived meanwhile is newer, so it stays on top.
        let previous = history
        history = Array((history + kept).prefix(Self.chatLimit - 1))
        removeWorkspaces(leftFrom: previous + kept)
        Log.chat.info("\(kept.count) recent chat(s) back after a shake")
        return kept.count
    }

    /// Lets the chats a shake held aside go for good, workspaces and all.
    private func dropShakenChats() {
        shakenChatsTask?.cancel()
        shakenChatsTask = nil
        guard !shakenChats.isEmpty else { return }
        for chat in shakenChats { chat.workspace?.remove() }
        Log.chat.info("\(shakenChats.count) recent chat(s) shaken away for good")
        shakenChats = []
    }

    /// Forgets every chat at once, as quitting does: the open one, with what is typed in it and the text on offer,
    /// and Recent Chats, workspaces and all. An answer still coming stops. The games' tally stays, since it holds
    /// no word of any chat. Says how many chats went.
    @discardableResult
    func forgetAll() -> Int {
        let open = turns.isEmpty ? 0 : 1
        reset(keepingChat: false)
        offeredSelection = nil
        return open + forgetHistory()
    }

    /// The buttons beside the timer under the card: the open chat gets `minutes` more, on top of what it has.
    func addTime(minutes: Int) {
        guard expiresAt != nil else { return }
        deadline = max(deadline, .now).addingTimeInterval(TimeInterval(minutes * 60))
        Log.chat.info("Chat given \(minutes) more minutes")
    }

    /// Lets go of every chat whose time is up, workspaces and all: those in Recent Chats, and the open one unless
    /// an answer is still coming, since the end of the answer starts its time over. Runs at each deadline, and
    /// when the window opens in case the Mac slept through one.
    func expireChats(now: Date = .now) {
        let expired = history.filter { $0.expiresAt <= now }
        if !expired.isEmpty {
            history.removeAll { $0.expiresAt <= now }
            for chat in expired { chat.workspace?.remove() }
            Log.chat.info("\(expired.count) recent chat(s) ran out of time")
        }
        if let expiresAt, expiresAt <= now, !isStreaming {
            expireOpenChat()
        }
        scheduleExpiry()
    }

    /// The open chat ran out of time: it goes, workspace and all, without passing through Recent Chats. What is
    /// typed in the input and on the Context card stays, for a new chat, Live's questions and answers with it. A
    /// game ends; its score against the model stays.
    private func expireOpenChat() {
        let kind = isPlaying ? "Game" : "Chat"
        let typed = currentDraft
        reset(keepingChat: false)
        restore(typed)
        Log.chat.info("\(kind) ran out of time")
    }

    /// Gives the open chat its `chatLifetime` again, or leaves it the time it has when that is more, as after
    /// `addTime(minutes:)`.
    private func restartClock(at now: Date = .now) {
        let fresh = now.addingTimeInterval(Self.chatLifetime)
        deadline = deadline == .distantFuture ? fresh : max(deadline, fresh)
    }

    /// Sleeps until the next chat's time is up. While an answer streams, the open chat's time waits for it.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        let open = isStreaming ? nil : expiresAt
        guard let next = (history.map(\.expiresAt) + [open].compactMap { $0 }).min() else {
            expiryTask = nil
            return
        }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.expireChats()
        }
    }

    func clearDraft() {
        draft = ""
        draftImages = []
        draftFiles = []
        draftSelections = []
        typedState = nil
        explainedScope = nil
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

    /// A picture selected in another app, such as Preview or Photos, and handed over by the Services menu, for
    /// either mode. The same picture comes only once, as the same text does.
    func bring(_ image: NSImage) {
        guard !isPlaying, let attachment = try? ImageAttachment.make(from: image) else {
            // A game's nudge, or why the picture can't go in.
            return attach(image)
        }
        guard !draftImages.contains(where: { $0.data == attachment.data }) else { return }
        attach { attachment }
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
    /// one for an LLM or an agent; anything else only while asking an agent, since an LLM can't read it, unless
    /// they were handed over `deliberately` (the Services menu), which brings everything, like a drop. A decision
    /// reads text only, and a game has no use for them.
    func bring(files urls: [URL], deliberately: Bool = false) {
        guard !isPlaying else { return }
        let usable = deliberately || preferences.mode == .agent ? urls : preferences.mode == .decision ? [] : urls.filter(ImageAttachment.isImage(at:))
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

    /// Copies the last answer: its Markdown as plain text, and the same answer as HTML and RTF for apps that
    /// take rich text (see `AnswerExport`).
    func copyLastAnswer() {
        guard let lastAnswer else { return }
        AnswerExport.copy(lastAnswer, to: .general)
        usage.record(as: lastAnswerKind) { $0.answersCopied += 1 }
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
            let handed = turn.presentedFiles.isEmpty ? "" : "\n\n_\(turn.presentedFiles.map(\.name).joined(separator: ", ")) handed over_"
            return "**You**\n\n\(asked)\n\n**Assistant**\n\n\(turn.answer.trimmed)\(handed)"
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
        // Text that waits goes in ahead of whatever came after it, so nothing shows out of order: a tool, an
        // ask, or a file never shows before the words the model wrote first. What an answer took is no part of
        // what shows, and Gemini reports it with every chunk, so it leaves the text waiting.
        switch output {
        case .text, .usage: break
        default: addHeldText()
        }
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
            } else if turns[last].answer.isEmpty {
                // An answer's first words show at once, in the thinking line's place.
                turns[last].answer = text
            } else {
                hold(text)
                return
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
        case .usage(let usage, let adds):
            turns[last].usage = (turns[last].usage ?? .zero).merging(usage, adding: adds)
        case .decision(let decision):
            turns[last].decision = decision
            turns[last].answer = decision.summary(unsureBelow: preferences.unsureBelow)
            turns[last].activity = nil
        case .decisions(let batch):
            turns[last].decisions = batch
            turns[last].answer = batch.summary(unsureBelow: preferences.unsureBelow)
            turns[last].activity = nil
        case .presetDecisions(let round):
            turns[last].presetDecisions = round
            turns[last].answer = round.summary(unsureBelow: preferences.unsureBelow)
            turns[last].activity = nil
        case .presented(let paths):
            // Read as Meraline's MCP server read it, so these are the files the agent was told it handed over.
            guard let workspace else { return }
            let handed = PresentedFile.handOver(paths, in: workspace.url).files
                .filter { file in !turns[last].presentedFiles.contains { $0.id == file.id } }
            guard !handed.isEmpty else { return }
            turns[last].presentedFiles += handed
            Log.chat.info("Agent handed over \(handed.count) file(s)")
        }
    }

    /// Keeps streamed text back until `textInterval` after the first of it came, then adds all that came
    /// meanwhile to the answer in one go. Counting from the text's arrival, not from the last time the answer
    /// grew, leaves the stream that long to be read between two layouts however long a layout takes, so a slow
    /// one takes in everything that queued behind it instead of a chunk at a time.
    private func hold(_ text: String) {
        heldText += text
        guard heldTextTask == nil else { return }
        let interval = textInterval
        heldTextTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.addHeldText()
        }
    }

    /// Adds the streamed text that waited to the answer of the last turn, the one that streams: when its time
    /// is up, ahead of anything else the stream brings, and before the answer ends, fails, or is stopped, so a
    /// turn that is done holds every character that arrived.
    private func addHeldText() {
        heldTextTask?.cancel()
        heldTextTask = nil
        guard !heldText.isEmpty, let last = turns.indices.last else { return }
        turns[last].answer += heldText
        turns[last].activity = nil
        heldText = ""
    }

    /// Keeps the trail of tools an answer used. Thinking is not a tool. An agent often announces a tool
    /// twice, first by name and then with what it was asked, so a repeat of the last step fills it in
    /// rather than adding a second one; the same step with new details, like a second search, is added.
    nonisolated static func record(_ activity: Activity, in tools: inout [Activity]) {
        guard activity != .thinking, activity != .presenting else { return }
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

    /// Works out what to ask after `turn`, the last one, in place of what was suggested before. Only a chat's
    /// finished answer gets any: not a game's move, nor an answer still coming.
    private func suggestFollowUps(after turn: Turn?) {
        clearFollowUps()
        // An answer that is the question's text, changed (see `findChanges`), is something to use, not a subject:
        // asked about a corrected note, the suggestions took the note for one ("Who is receiving the package?").
        guard let turn, !isPlaying, !isStreaming, turn.isComplete, !turn.answer.trimmed.isEmpty, !turn.isDecision, turn.changes == nil else { return }
        let request = FollowUps.Request(question: turn.question, answer: turn.answer, asked: turns.map(\.question), language: preferences.language)
        let suggest = followUpSuggester
        followUpTask = Task { [weak self] in
            let questions = await suggest(request)
            guard let self, !Task.isCancelled, !isStreaming, turns.last?.id == turn.id else { return }
            followUpTask = nil
            followUpLoadingTask?.cancel()
            followUpLoadingTask = nil
            isSuggestingFollowUps = false
            followUps = questions
            if !questions.isEmpty { Log.chat.info("\(questions.count) follow-ups suggested") }
        }
        followUpLoadingTask = Task { [weak self] in
            try? await Task.sleep(for: FollowUps.loadingDelay)
            guard let self, !Task.isCancelled, followUpTask != nil else { return }
            isSuggestingFollowUps = true
        }
    }

    private func clearFollowUps() {
        followUpTask?.cancel()
        followUpTask = nil
        followUpLoadingTask?.cancel()
        followUpLoadingTask = nil
        if isSuggestingFollowUps { isSuggestingFollowUps = false }
        if !followUps.isEmpty { followUps = [] }
    }

    private func finishStreaming(_ id: Turn.ID, error: Error?) {
        guard isStreaming, turns.last?.id == id else { return }
        addHeldText()
        isStreaming = false
        restartClock()
        streamTask = nil
        responders = [:]
        let replaced = replacedTurn
        replacedTurn = nil
        let wasRewriting = isRewriting
        isRewriting = false
        let last = turns.count - 1
        turns[last].activity = nil
        turns[last].prompts.removeAll(where: \.isPending)
        if let game {
            finishMove(in: game, error: error)
            return
        }
        let wasStopped = error is CancellationError || (error as? URLError)?.code == .cancelled
        count(error == nil ? .complete : wasStopped ? .stopped : .failed, of: turns[last], tools: !wasRewriting)

        if wasRewriting, error == nil, let replaced {
            rewritten.append((before: replaced, after: turns[last].id))
        }
        // A rewrite stopped or failed partway gives the old answer back rather than keep half of the new one.
        if wasRewriting, let error, let replaced {
            turns[last] = replaced
            suggestFollowUps(after: replaced)
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                Log.chat.info("Rewrite stopped; the old answer is back")
            } else {
                Log.chat.error("Rewrite failed: \(error.localizedDescription)")
                fail(with: error.localizedDescription, needsSettings: Self.needsSettings(error))
                failureRetry = .askAgain
            }
            return
        }

        guard let error, !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
            turns[last].isComplete = !turns[last].answer.isEmpty
            if turns[last].answer.isEmpty {
                Log.chat.info("Answer stopped before any text arrived")
                takeBackQuestion(restoring: replaced)
            } else {
                Log.chat.info("Answer \(error == nil ? "complete" : "stopped"), \(turns[last].answer.count) characters")
                // A stopped answer is cut short, so nothing follows on from it.
                if error == nil { suggestFollowUps(after: turns[last]) }
                if error == nil { findChanges(at: last) }
            }
            return
        }
        Log.chat.error("Answer failed: \(error.localizedDescription)")

        // The question comes back to the input when no answer came, unless Ask Again asked it, which puts the
        // answer it was to replace back instead; Try Again then sends it or asks again accordingly.
        let cameBack = turns[last].answer.isEmpty && replaced == nil
        let presets = turns[last].presetDecisions
        if turns[last].answer.isEmpty {
            takeBackQuestion(restoring: replaced)
        } else {
            turns[last].isComplete = true
        }
        fail(with: error.localizedDescription, needsSettings: Self.needsSettings(error))
        failureRetry = cameBack ? presets.map { .askPresets($0.cleared) } ?? .send : .askAgain
    }

    /// Looks for what the finished answer at `index` changed in the text its question was about, or, for a
    /// follow-up about none, in the texts of the last question before it that had some, all of them together too.
    /// A stopped or failed answer is cut short, so it has none. A long text rearranged throughout takes a moment to
    /// compare, so it happens off the main actor, and a turn that has gone meanwhile is left be.
    private func findChanges(at index: Int) {
        guard !turns[index].isDecision, let selections = turns[...index].last(where: { !$0.selections.isEmpty })?.selections else { return }
        let texts = selections.map(\.text)
        let originals = texts.count > 1 ? texts + [texts.joined(separator: "\n\n")] : texts
        let id = turns[index].id
        let answer = turns[index].answer
        changesSearch = Task { [weak self] in
            let changes = await Task.detached(priority: .userInitiated) { TextChanges.find(in: answer, against: originals) }.value
            guard let self, let changes, let index = self.turns.firstIndex(where: { $0.id == id }) else { return }
            self.turns[index].changes = changes
            Log.chat.info("The answer changes the text in \(changes.count) place(s)")
            // The follow-ups asked for when the answer ended, coming or already here, go (see `suggestFollowUps`).
            if index == self.turns.count - 1 { self.clearFollowUps() }
        }
    }

    /// An answer that brought no text goes: its question returns to the input, or, when Ask Again asked it,
    /// the answer it was to replace comes back and the input stays as it is.
    private func takeBackQuestion(restoring replaced: Turn?) {
        let turn = turns.removeLast()
        if let replaced {
            turns.append(replaced)
            suggestFollowUps(after: replaced)
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
            count(.failed, of: turns[last], inGame: true)
            takeBackLastTurn()
            fail(with: error.localizedDescription, needsSettings: Self.needsSettings(error))
            return
        }
        guard !wasStopped, !turns[last].answer.trimmed.isEmpty else {
            Log.chat.info("\(game.title): the model's move stopped")
            count(.stopped, of: turns[last], inGame: true)
            takeBackLastTurn()
            return
        }
        count(.complete, of: turns[last], inGame: true)
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
        case .retry(let reply, let cue):
            turns[last].answer = reply
            turns[last].isComplete = true
            Log.chat.info("\(game.title): the model's move broke the rules; asking once more, turn \(turns.count)")
            askModel(cue, in: game)
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
        // The presets' titles are no question of yours: the input keeps what it had.
        if turn.presetDecisions == nil { draft = turn.question }
        draftImages = turn.images
        draftFiles = turn.files
        draftSelections = turn.selections
    }

    private func fail(with message: String, needsSettings: Bool = false) {
        failure = message
        failureNeedsSettings = needsSettings
    }
}
