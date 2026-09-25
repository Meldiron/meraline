import Foundation
import FoundationModels

/// Answers with the on-device model that ships with macOS, through Apple's Foundation Models framework.
///
/// Nothing leaves the Mac and no key is needed, but the model is small: its context window holds about
/// 4,000 tokens, it can't look at images on macOS 26, and its safety filters are strict. The client
/// trims old turns until a request fits and turns the framework's errors into plain sentences.
nonisolated enum AppleIntelligenceClient {
    static var availability: SystemLanguageModel.Availability { SystemLanguageModel.default.availability }

    static var isAvailable: Bool { availability == .available }

    static func explanation(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "This Mac can’t run Apple Intelligence."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in System Settings to use the on-device model."
        case .modelNotReady: "Apple Intelligence is still downloading its model. Try again in a little while."
        @unknown default: "Apple Intelligence isn’t available right now."
        }
    }

    /// Loads the model into memory so the first answer starts sooner.
    static func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession().prewarm()
    }

    /// Rebuilds a session from Meraline's own history, keeping only the last `turns` question-and-answer pairs.
    static func transcript(systemPrompt: String, history: [ChatMessage], keepingLast turns: Int) -> Transcript {
        var entries: [Transcript.Entry] = []
        if !systemPrompt.trimmed.isEmpty {
            entries.append(.instructions(.init(segments: [.text(.init(content: systemPrompt))], toolDefinitions: [])))
        }
        for message in history.suffix(max(turns, 0) * 2) {
            let segments: [Transcript.Segment] = [.text(.init(content: text(of: message)))]
            switch message.role {
            case .user: entries.append(.prompt(.init(segments: segments)))
            case .assistant: entries.append(.response(.init(assetIDs: [], segments: segments)))
            }
        }
        return Transcript(entries: entries)
    }

    /// The framework streams whole snapshots of the answer so far; Meraline wants only what's new.
    /// Returns nil when a snapshot doesn't extend the text already shown.
    static func delta(from shown: String, to snapshot: String) -> String? {
        guard snapshot.hasPrefix(shown) else { return nil }
        return String(snapshot.dropFirst(shown.count))
    }

    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if case .unavailable(let reason) = availability {
                        throw LLMError.provider(explanation(for: reason))
                    }
                    guard let question = request.messages.last else { throw LLMError.emptyResponse }
                    if !question.images.isEmpty {
                        throw LLMError.provider("Apple Intelligence can’t look at images on this version of macOS. Switch to another provider for this question.")
                    }

                    let history = Array(request.messages.dropLast())
                    var turnsToKeep = history.count / 2
                    var shown = ""
                    while true {
                        let session = LanguageModelSession(
                            transcript: transcript(systemPrompt: request.systemPrompt, history: history, keepingLast: turnsToKeep)
                        )
                        do {
                            for try await snapshot in session.streamResponse(to: text(of: question)) {
                                try Task.checkCancellation()
                                guard let delta = delta(from: shown, to: snapshot.content), !delta.isEmpty else { continue }
                                shown = snapshot.content
                                continuation.yield(.text(delta))
                            }
                            break
                        } catch LanguageModelSession.GenerationError.exceededContextWindowSize(_) where shown.isEmpty && turnsToKeep > 0 {
                            turnsToKeep -= 1
                        }
                    }
                    if shown.isEmpty { throw LLMError.emptyResponse }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: map(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func map(_ error: LanguageModelSession.GenerationError) -> LLMError {
        switch error {
        case .guardrailViolation:
            .provider("Apple Intelligence’s safety filter stopped this request. Try rephrasing it, or switch to another provider.")
        case .refusal:
            .refused
        case .exceededContextWindowSize:
            .provider("This chat is longer than Apple Intelligence can hold in memory. Start a new chat or switch to another provider.")
        case .unsupportedLanguageOrLocale:
            .provider("Apple Intelligence doesn’t support this language yet.")
        case .rateLimited:
            .provider("Apple Intelligence is pausing requests for a moment. Try again shortly.")
        case .concurrentRequests:
            .provider("Apple Intelligence is already working on another request.")
        case .assetsUnavailable:
            .provider("Apple Intelligence is still downloading its model. Try again in a little while.")
        case .unsupportedGuide, .decodingFailure:
            .provider(error.errorDescription ?? "Apple Intelligence couldn’t answer.")
        @unknown default:
            .provider(error.errorDescription ?? "Apple Intelligence couldn’t answer.")
        }
    }

    private static func text(of message: ChatMessage) -> String {
        if message.text.isEmpty && !message.images.isEmpty { return "(An image was attached, but this model can’t see images.)" }
        return message.text
    }
}
