import AppKit
import Observation

@Observable
final class ChatSession {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let images: [ImageAttachment]
        var answer = ""
        var activity: Activity?
        var isComplete = false
        var startsOverOnNextText = false
    }

    struct PastChat: Identifiable, Equatable {
        let id = UUID()
        let turns: [Turn]
        let date: Date

        var title: String {
            let question = turns.first?.question ?? ""
            return question.isEmpty ? "Image question" : question
        }
    }

    static let historyLimit = 5

    var draft = ""
    private(set) var draftImages: [ImageAttachment] = []
    private(set) var turns: [Turn] = []
    private(set) var history: [PastChat] = []
    private(set) var isStreaming = false
    private(set) var failure: String?
    private(set) var failureNeedsSettings = false

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    var canSend: Bool {
        !isStreaming && (!draft.trimmed.isEmpty || !draftImages.isEmpty)
    }

    var lastAnswer: String? {
        turns.last(where: { !$0.answer.isEmpty })?.answer
    }

    func send() {
        guard canSend else { return }
        guard let provider = preferences.activeProvider else {
            fail(with: "Connect an AI provider in Settings to start asking.", needsSettings: true)
            return
        }

        let question = draft.trimmed
        let images = draftImages
        let history = turns.filter(\.isComplete).flatMap { turn in
            [
                ChatMessage(role: .user, text: turn.question, images: turn.images),
                ChatMessage(role: .assistant, text: turn.answer)
            ]
        }
        let request = ChatRequest(
            provider: provider,
            settings: preferences[provider],
            systemPrompt: preferences.systemPrompt,
            messages: history + [ChatMessage(role: .user, text: question, images: images)]
        )

        draft = ""
        draftImages = []
        failure = nil
        let turn = Turn(question: question, images: images)
        turns.append(turn)
        isStreaming = true
        let model = preferences[provider].model.trimmed
        Log.chat.info("Asking \(provider.name) (\(model.isEmpty ? "default model" : model)), turn \(turns.count), \(images.count) image(s)")

        streamTask = Task { [weak self] in
            do {
                for try await output in LLMClient.stream(request) {
                    self?.receive(output, for: turn.id)
                }
                self?.finishStreaming(turn.id, error: nil)
            } catch {
                self?.finishStreaming(turn.id, error: error)
            }
        }
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
        isStreaming = false
        failure = nil
        failureNeedsSettings = false
    }

    func reopen(_ id: PastChat.ID) {
        guard let chat = history.first(where: { $0.id == id }) else { return }
        history.removeAll { $0.id == id }
        reset()
        turns = chat.turns
    }

    /// The window came back after being hidden for a long time: the chat moves to Recent Chats and the
    /// next question starts fresh. Anything typed but not yet sent stays in the input.
    func expire() {
        guard !isStreaming, !turns.isEmpty else { return }
        archiveCurrentChat()
        turns = []
        failure = nil
        failureNeedsSettings = false
    }

    private func archiveCurrentChat() {
        history = Self.archiving(turns, into: history)
    }

    static func archiving(_ turns: [Turn], into history: [PastChat], at date: Date = .now) -> [PastChat] {
        let answered = turns
            .filter { !$0.answer.isEmpty }
            .map { turn in
                var turn = turn
                turn.activity = nil
                turn.isComplete = true
                return turn
            }
        guard !answered.isEmpty else { return history }
        return Array(([PastChat(turns: answered, date: date)] + history).prefix(historyLimit))
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

    var conversationMarkdown: String? { Self.markdown(for: turns) }

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
        let needsSettings: Bool = switch error as? LLMError {
        case .missingKey, .invalidBaseURL: true
        case .http(let status, _): status == 401 || status == 403 || status == 404
        default: false
        }
        fail(with: error.localizedDescription, needsSettings: needsSettings)
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
