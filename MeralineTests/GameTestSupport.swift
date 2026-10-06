import AppKit
import Foundation
@testable import Meraline

/// Stands in for the provider in game tests: answers each request with the next scripted reply, and
/// remembers every request it was sent. With no reply left, the request fails like an empty answer.
@MainActor
final class ScriptedModel {
    var replies: [String]
    /// What each reply says it took, in order, for a model that reports its usage.
    var usage: [TokenUsage]
    /// What each question in Decision mode is answered with, in order (see `Decision`), Decision's presets asked at
    /// once taking one each (see `PresetDecisions`), and what each question about every word or line is answered
    /// with (see `DecisionBatch`).
    var decisions: [Decision]
    var batches: [DecisionBatch]
    private(set) var requests: [ChatRequest] = []

    init(_ replies: [String] = [], usage: [TokenUsage] = [], decisions: [Decision] = [], batches: [DecisionBatch] = []) {
        self.replies = replies
        self.usage = usage
        self.decisions = decisions
        self.batches = batches
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        requests.append(request)
        let took = usage.isEmpty ? nil : usage.removeFirst()
        if let presets = request.decision?.presets, !decisions.isEmpty {
            // Every question of the round answered in one reply, as many as there are answers left.
            var round = presets
            var answers: [DecisionQuestion.ID: Decision] = [:]
            for question in round.undecided where !decisions.isEmpty { answers[question.id] = decisions.removeFirst() }
            round.take(answers)
            return AsyncThrowingStream { continuation in
                if let took { continuation.yield(.usage(took, adds: true)) }
                continuation.yield(.presetDecisions(round))
                continuation.finish()
            }
        }
        if let decision = request.decision, !decision.items.isEmpty, !batches.isEmpty {
            let batch = batches.removeFirst()
            return AsyncThrowingStream { continuation in
                if let took { continuation.yield(.usage(took, adds: true)) }
                continuation.yield(.decisions(batch))
                continuation.finish()
            }
        }
        if request.decision != nil, !decisions.isEmpty {
            let decision = decisions.removeFirst()
            return AsyncThrowingStream { continuation in
                if let took { continuation.yield(.usage(took, adds: false)) }
                continuation.yield(.decision(decision))
                continuation.finish()
            }
        }
        let reply = replies.isEmpty ? nil : replies.removeFirst()
        return AsyncThrowingStream { continuation in
            if let reply {
                continuation.yield(.text(reply))
                if let took { continuation.yield(.usage(took, adds: false)) }
                continuation.finish()
            } else {
                continuation.finish(throwing: LLMError.emptyResponse)
            }
        }
    }

    var lastMessages: [String] { requests.last?.messages.map(\.text) ?? [] }
}

@MainActor
enum GameTestSupport {
    /// Preferences with a ready provider, in a throwaway defaults suite and without the Keychain.
    static func preferences(withProvider: Bool = true) -> Preferences {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(
            defaults: defaults,
            secrets: SecretStore(read: { _ in "" }, write: { _, _ in }),
            onDeviceModelAvailable: false
        )
        if withProvider {
            preferences[.custom] = ProviderSettings(model: "games", baseURL: "http://127.0.0.1:9", apiKey: "", isEnabled: true)
        }
        return preferences
    }

    /// A session with a usage ledger of its own, in memory, so no test touches the app's.
    static func session(_ model: ScriptedModel, withProvider: Bool = true, usage: UsageLedger = UsageLedger(file: nil)) -> ChatSession {
        ChatSession(preferences: preferences(withProvider: withProvider), usage: usage) { model.stream($0) }
    }

    /// Waits until the model's move has arrived and been judged.
    static func settle(_ session: ChatSession) async {
        for _ in 0..<1_000 {
            guard session.isStreaming else { return }
            await Task.yield()
        }
    }

    /// Types a line and presses Return, then waits for any reply.
    static func play(_ line: String, in session: ChatSession) async {
        session.draft = line
        session.send()
        await settle(session)
    }

    nonisolated static func turn(_ question: String = "", cue: String? = nil, reply: String = "", outcome: GameOutcome? = nil) -> ChatSession.Turn {
        ChatSession.Turn(question: question, images: [], answer: reply, isComplete: true, cue: cue, outcome: outcome)
    }

    static func image() -> NSImage {
        NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
    }
}
