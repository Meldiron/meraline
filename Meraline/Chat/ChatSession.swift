import AppKit
import Observation

@Observable
final class ChatSession {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let images: [ImageAttachment]
        var answer = ""
        var isComplete = false
    }

    var draft = ""
    private(set) var draftImages: [ImageAttachment] = []
    private(set) var turns: [Turn] = []
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

        streamTask = Task { [weak self] in
            do {
                for try await text in LLMClient.stream(request) {
                    self?.append(text, to: turn.id)
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
        streamTask?.cancel()
        streamTask = nil
        draft = ""
        draftImages = []
        turns = []
        isStreaming = false
        failure = nil
        failureNeedsSettings = false
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

    private func append(_ text: String, to id: Turn.ID) {
        guard turns.last?.id == id else { return }
        turns[turns.count - 1].answer += text
    }

    private func finishStreaming(_ id: Turn.ID, error: Error?) {
        guard isStreaming, turns.last?.id == id else { return }
        isStreaming = false
        streamTask = nil
        let last = turns.count - 1

        guard let error, !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
            turns[last].isComplete = !turns[last].answer.isEmpty
            if turns[last].answer.isEmpty { restoreDraft(from: turns.removeLast()) }
            return
        }

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
