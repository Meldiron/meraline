import Foundation
import FoundationModels
import Testing
@testable import Meraline

struct AppleIntelligenceTests {
    private let history = [
        ChatMessage(role: .user, text: "First?"),
        ChatMessage(role: .assistant, text: "One."),
        ChatMessage(role: .user, text: "Second?"),
        ChatMessage(role: .assistant, text: "Two.")
    ]

    @Test func transcriptStartsWithInstructionsAndKeepsTheNewestTurns() {
        let full = AppleIntelligenceClient.transcript(systemPrompt: "Be brief.", history: history, keepingLast: 2)
        #expect(full.count == 5)
        guard case .instructions(let instructions) = full[0] else { Issue.record("missing instructions"); return }
        #expect(instructions.segments.count == 1)
        guard case .prompt(let prompt) = full[1], case .response(let response) = full[2] else {
            Issue.record("history isn’t prompt then response"); return
        }
        guard case .text(let question) = prompt.segments.first, case .text(let answer) = response.segments.first else {
            Issue.record("segments aren’t text"); return
        }
        #expect(question.content == "First?")
        #expect(answer.content == "One.")

        let trimmed = AppleIntelligenceClient.transcript(systemPrompt: "Be brief.", history: history, keepingLast: 1)
        #expect(trimmed.count == 3)
        guard case .prompt(let newest) = trimmed[1], case .text(let text) = newest.segments.first else {
            Issue.record("trimmed transcript lost the newest turn"); return
        }
        #expect(text.content == "Second?")

        let bare = AppleIntelligenceClient.transcript(systemPrompt: " ", history: history, keepingLast: 0)
        #expect(bare.isEmpty)
    }

    @Test func snapshotsBecomeDeltas() {
        #expect(AppleIntelligenceClient.delta(from: "", to: "Par") == "Par")
        #expect(AppleIntelligenceClient.delta(from: "Par", to: "Paris.") == "is.")
        #expect(AppleIntelligenceClient.delta(from: "Paris.", to: "Paris.") == "")
        #expect(AppleIntelligenceClient.delta(from: "Paris.", to: "Lyon.") == nil)
    }

    @Test func frameworkErrorsBecomePlainSentences() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let blocked = AppleIntelligenceClient.map(.guardrailViolation(context))
        guard case .provider(let message) = blocked else { Issue.record("expected a provider error"); return }
        #expect(message.contains("safety filter"))
        #expect(AppleIntelligenceClient.map(.rateLimited(context)) != .emptyResponse)
        #expect(AppleIntelligenceClient.explanation(for: .appleIntelligenceNotEnabled).contains("System Settings"))
    }

    @Test func onDeviceProviderNeedsNoKeyModelOrServer() {
        #expect(Provider.apple.isOnDevice)
        #expect(Provider.apple.keyPolicy == .none)
        #expect(Provider.apple.defaultModel.isEmpty && Provider.apple.defaultBaseURL.isEmpty)
        #expect(!Provider.apple.isCommandLine)
        #expect(Provider.allCases.last == .apple, "the on-device model is the fallback, so it sorts after configured providers")
    }

    @Test(.enabled(if: AppleIntelligenceClient.isAvailable))
    func onDeviceModelAnswers() async throws {
        let request = ChatRequest(
            provider: .apple,
            settings: ProviderSettings(model: "", baseURL: "", apiKey: "", isEnabled: true),
            systemPrompt: "Reply with exactly one lowercase word.",
            messages: [ChatMessage(role: .user, text: "Say ready.")]
        )
        var answer = ""
        for try await output in LLMClient.stream(request) {
            if case .text(let text) = output { answer += text }
        }
        #expect(answer.lowercased().contains("ready"), "Apple Intelligence answered: \(answer)")
    }
}
