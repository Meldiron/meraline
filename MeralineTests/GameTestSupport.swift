import AppKit
import Foundation
@testable import Meraline

/// Stands in for the provider in game tests: answers each request with the next scripted reply, and
/// remembers every request it was sent. With no reply left, the request fails like an empty answer.
@MainActor
final class ScriptedModel {
    var replies: [String]
    private(set) var requests: [ChatRequest] = []

    init(_ replies: [String] = []) {
        self.replies = replies
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        requests.append(request)
        let reply = replies.isEmpty ? nil : replies.removeFirst()
        return AsyncThrowingStream { continuation in
            if let reply {
                continuation.yield(.text(reply))
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

    static func session(_ model: ScriptedModel, withProvider: Bool = true) -> ChatSession {
        ChatSession(preferences: preferences(withProvider: withProvider)) { model.stream($0) }
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
