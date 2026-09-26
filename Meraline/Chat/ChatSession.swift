import AppKit
import Observation

@Observable
final class ChatSession {
    /// What the open chat is: quick questions, or one of the games in the sparkle menu (see `Game`).
    enum Mode: Equatable {
        case chat
        case game(Game)
    }

    /// A question and its answer. In a game, a move and the model's reply (see `GameRules`).
    nonisolated struct Turn: Identifiable, Equatable, Sendable {
        let id = UUID()
        let question: String
        let images: [ImageAttachment]
        var answer = ""
        var activity: Activity?
        var isComplete = false
        var startsOverOnNextText = false
        /// In a game, what the model was asked when it moved on its own; nil for a move of yours.
        var cue: String?
        /// In a game, how the round settled on this Mac.
        var outcome: GameOutcome?
    }

    struct PastChat: Identifiable, Equatable {
        let id = UUID()
        let turns: [Turn]
        let date: Date
        var mode = Mode.chat

        var title: String {
            let question = turns.first?.question ?? ""
            switch mode {
            case .chat:
                return question.isEmpty ? "Image question" : question
            case .game(let game):
                return game.rules.headline(of: turns).map { "\(game.title): \($0)" } ?? game.title
            }
        }
    }

    static let historyLimit = 5

    var draft = ""
    private(set) var draftImages: [ImageAttachment] = []
    private(set) var turns: [Turn] = []
    private(set) var history: [PastChat] = []
    private(set) var mode = Mode.chat
    private(set) var isStreaming = false
    private(set) var failure: String?
    private(set) var failureNeedsSettings = false
    /// A friendly line from a game: its invitation, why a move came back, or that the round is over.
    /// Unlike `failure`, nothing went wrong.
    private(set) var nudge: String?

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    /// The game move that came back last; sending it again unchanged insists on it.
    @ObservationIgnored private var insistedInput: String?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let streamReplies: @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error>

    /// `stream` talks to the provider; tests pass one that replies on its own.
    init(preferences: Preferences, stream: @escaping @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> = LLMClient.stream) {
        self.preferences = preferences
        streamReplies = stream
    }

    var canSend: Bool {
        guard !isStreaming else { return false }
        guard let gameState else { return !draft.trimmed.isEmpty || !draftImages.isEmpty }
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

    var lastAnswer: String? {
        turns.last(where: { !$0.answer.isEmpty })?.answer
    }

    func send() {
        guard canSend else { return }
        if let game {
            play(game)
            return
        }
        guard let provider = preferences.activeProvider else {
            fail(with: "Connect an AI provider in Settings to start asking.", needsSettings: true)
            return
        }
        let question = draft.trimmed
        let images = draftImages
        let request = makeRequest(asking: question, images: images, of: provider)

        draft = ""
        draftImages = []
        failure = nil
        let turn = Turn(question: question, images: images)
        turns.append(turn)
        isStreaming = true
        Log.chat.info("Asking \(provider.name) (\(modelName(for: provider))), turn \(turns.count), \(images.count) image(s)")
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
                    fail(with: "Connect an AI provider in Settings to play.", needsSettings: true)
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
        case .over(let summary, _):
            Log.chat.info("\(game.title): round over")
            nudge = summary
        default:
            break
        }
    }

    /// Asks the model for a move of its own: a turn with a cue and nothing of yours. If that fails,
    /// Return asks again.
    private func askModel(_ cue: String, in game: Game) {
        guard let provider = preferences.activeProvider else {
            fail(with: "Connect an AI provider in Settings to play.", needsSettings: true)
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
    func makeRequest(asking question: String, images: [ImageAttachment], of provider: Provider) -> ChatRequest {
        var messages: [ChatMessage] = []
        func add(_ role: ChatMessage.Role, _ text: String, _ images: [ImageAttachment] = []) {
            guard !text.isEmpty || !images.isEmpty else { return }
            if let previous = messages.last, previous.role == role {
                let joined = [previous.text, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                messages[messages.count - 1] = ChatMessage(role: role, text: joined, images: previous.images + images)
            } else {
                messages.append(ChatMessage(role: role, text: text, images: images))
            }
        }
        for turn in turns where turn.isComplete {
            add(.user, turn.cue ?? turn.question, turn.images)
            add(.assistant, turn.answer)
        }
        add(.user, question, images)
        return ChatRequest(
            provider: provider,
            settings: preferences[provider],
            systemPrompt: game?.rules.systemPrompt ?? preferences.systemPrompt,
            messages: messages
        )
    }

    func stop() {
        guard isStreaming else { return }
        streamTask?.cancel()
    }

    func reset() {
        archiveCurrentChat()
        streamTask?.cancel()
        streamTask = nil
        draft = ""
        draftImages = []
        turns = []
        mode = .chat
        isStreaming = false
        failure = nil
        failureNeedsSettings = false
        nudge = nil
        insistedInput = nil
    }

    /// Starts a game in place of the open chat, which moves to Recent Chats first. The model moves first.
    func startGame(_ game: Game) {
        reset()
        mode = .game(game)
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

    func reopen(_ id: PastChat.ID) {
        guard let chat = history.first(where: { $0.id == id }) else { return }
        history.removeAll { $0.id == id }
        reopen(chat)
    }

    /// Makes a past chat the open one, in the mode it was in. Whatever was open moves to Recent Chats.
    func reopen(_ chat: PastChat) {
        reset()
        turns = chat.turns
        mode = chat.mode
        if case .over(let summary, _)? = gameState?.phase { nudge = summary }
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

    private func archiveCurrentChat() {
        history = Self.archiving(turns, into: history, mode: mode)
    }

    static func archiving(_ turns: [Turn], into history: [PastChat], mode: Mode = .chat, at date: Date = .now) -> [PastChat] {
        let answered = turns
            .filter { !$0.answer.isEmpty || $0.isComplete }
            .map { turn in
                var turn = turn
                turn.activity = nil
                turn.isComplete = true
                return turn
            }
        guard !answered.isEmpty else { return history }
        return Array(([PastChat(turns: answered, date: date, mode: mode)] + history).prefix(historyLimit))
    }

    func clearDraft() {
        draft = ""
        draftImages = []
        failure = nil
    }

    func attach(_ image: NSImage) {
        attach { try ImageAttachment.make(from: image) }
    }

    func attach(fileAt url: URL) {
        attach { try ImageAttachment.load(from: url) }
    }

    func removeImage(_ id: ImageAttachment.ID) {
        draftImages.removeAll { $0.id == id }
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
            if !turn.images.isEmpty {
                let note = turn.images.count == 1 ? "1 image attached" : "\(turn.images.count) images attached"
                question += question.isEmpty ? "_\(note)_" : " _(\(note))_"
            }
            return "**You**\n\n\(question)\n\n**Assistant**\n\n\(turn.answer.trimmed)"
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
            turns[last].startsOverOnNextText = !turns[last].answer.isEmpty
        case .text(let text):
            if turns[last].startsOverOnNextText {
                turns[last].answer = text
                turns[last].startsOverOnNextText = false
            } else {
                turns[last].answer += text
            }
            turns[last].activity = nil
        }
    }

    private func finishStreaming(_ id: Turn.ID, error: Error?) {
        guard isStreaming, turns.last?.id == id else { return }
        isStreaming = false
        streamTask = nil
        let last = turns.count - 1
        turns[last].activity = nil
        if let game {
            finishMove(in: game, error: error)
            return
        }

        guard let error, !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
            turns[last].isComplete = !turns[last].answer.isEmpty
            if turns[last].answer.isEmpty {
                Log.chat.info("Answer stopped before any text arrived")
                restoreDraft(from: turns.removeLast())
            } else {
                Log.chat.info("Answer \(error == nil ? "complete" : "stopped"), \(turns[last].answer.count) characters")
            }
            return
        }
        Log.chat.error("Answer failed: \(error.localizedDescription)")

        if turns[last].answer.isEmpty {
            restoreDraft(from: turns.removeLast())
        } else {
            turns[last].isComplete = true
        }
        fail(with: error.localizedDescription, needsSettings: Self.needsSettings(error))
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
    }

    private func fail(with message: String, needsSettings: Bool = false) {
        failure = message
        failureNeedsSettings = needsSettings
    }
}
