import AppKit
import Carbon.HIToolbox
import Testing
@testable import Meraline

/// ⌘1 to ⌘9 on an agent's question with choices: each picks a choice as a click on it does. Until 2026-10-06 the
/// choices took the mouse alone, while Allow and Deny on a permission ask took Return.
@MainActor
struct PromptChoiceTests {
    private typealias Support = GameTestSupport

    private nonisolated final class Answers: @unchecked Sendable {
        private(set) var given: [AgentAnswer] = []
        var continuation: AsyncThrowingStream<StreamOutput, Error>.Continuation?
        func record(_ answer: AgentAnswer) { given.append(answer) }
    }

    private static func throwaway() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A chat whose agent asks `questions`, waiting for the answer in `answers`.
    private func asked(_ questions: [AgentPrompt.Question], preferences: Preferences, answers: Answers) async -> ChatSession {
        let prompt = AgentPrompt(id: "req-1", kind: .question(questions))
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in
            AsyncThrowingStream { continuation in
                answers.continuation = continuation
                continuation.yield(.prompt(prompt, AgentPromptResponder { answers.record($0) }))
            }
        }
        session.draft = "Draft a changelog entry"
        session.send()
        for _ in 0..<1_000 where session.turns.last?.pendingPrompt == nil { await Task.yield() }
        #expect(session.turns.last?.pendingPrompt?.id == "req-1")
        return session
    }

    private func context(_ session: ChatSession, preferences: Preferences, layout: PanelLayout = PanelLayout()) -> PanelContext {
        PanelContext(session: session, preferences: preferences, layout: layout, openSettings: { _ in })
    }

    /// ⌘ and a digit key as the key monitor hands it over, with what a Czech keyboard types on it.
    private func command(_ keyCode: Int, _ characters: String, in context: PanelContext) -> PanelAction? {
        context.action(forKeyCode: UInt16(keyCode), characters: characters, modifiers: .command)
    }

    @Test func theDigitsPickTheChoicesWhileAQuestionWaits() async {
        let preferences = Support.preferences()
        let answers = Answers()
        let release = AgentPrompt.Question(header: "Release", text: "Which release?", options: [.init(label: "1.3.0"), .init(label: "2.0.0", detail: "Breaking changes")])
        let session = await asked([release], preferences: preferences, answers: answers)
        let layout = PanelLayout()
        let context = context(session, preferences: preferences, layout: layout)

        #expect(context.promptChoices.map(\.id) == ["promptChoice.1", "promptChoice.2"], "a choice a digit")
        #expect(context.chatMenu?.actions.contains { $0.id.hasPrefix("promptChoice") } == false, "in no panel")
        let second = command(kVK_ANSI_2, "ě", in: context)
        #expect(second?.id == "promptChoice.2", "ahead of the mode toggle's ⌘2")
        #expect(second?.shortcut?.keycaps == ["⌘", "2"])
        #expect(command(kVK_ANSI_3, "š", in: context)?.id == "switchMode.decision", "two choices, two keys")

        second?.perform()
        #expect(layout.promptChoice == PanelLayout.PromptChoice(prompt: "req-1", index: 1, number: 1))
        second?.perform()
        #expect(layout.promptChoice?.number == 2, "pressed again is another press")

        // Answered, the keys go back to the modes.
        session.answer("req-1", with: .answers(["Which release?": "2.0.0"]))
        #expect(command(kVK_ANSI_2, "ě", in: context)?.id == "switchMode.agent")
        answers.continuation?.finish()
        await Support.settle(session)
    }

    @Test func onlyNineChoicesHaveKeys() async {
        let preferences = Support.preferences()
        let answers = Answers()
        let many = AgentPrompt.Question(text: "Which one?", options: (1...12).map { .init(label: "Choice \($0)") })
        let session = await asked([many], preferences: preferences, answers: answers)
        let context = context(session, preferences: preferences)
        #expect(context.promptChoices.count == 9)
        #expect(command(kVK_ANSI_9, "í", in: context)?.id == "promptChoice.9")
        #expect(command(kVK_ANSI_0, "é", in: context)?.id != "promptChoice.10")
        answers.continuation?.finish()
        await Support.settle(session)
    }

    /// The card in the app's own panel: a key picks the choice and, for one question with single choices, that
    /// answers the agent.
    @Test func aKeyAnswersTheAgentThroughTheCard() async throws {
        let defaults = Self.throwaway()
        defaults.set(true, forKey: ShortcutSetup.chosenKey)
        let preferences = Support.preferences()
        let answers = Answers()
        let release = AgentPrompt.Question(header: "Release", text: "Which release?", options: [.init(label: "1.3.0"), .init(label: "2.0.0")])
        let session = await asked([release], preferences: preferences, answers: answers)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: Updater(preferences: preferences, defaults: defaults), updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        let panel = try #require(NSApp.windows.first { $0 is FloatingPanel && !before.contains(ObjectIdentifier($0)) })
        controller.layout.isShown = true
        panel.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))

        let context = context(session, preferences: preferences, layout: controller.layout)
        let second = try #require(command(kVK_ANSI_2, "ě", in: context))
        context.run(second, in: .chat, fromShortcut: true)
        for _ in 0..<40 where answers.given.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(answers.given == [.answers(["Which release?": "2.0.0"])])
        #expect(session.turns.last?.pendingPrompt == nil)
        #expect(session.turns.last?.prompts.first?.resolution == .answered(["Which release?": "2.0.0"]))
        answers.continuation?.finish()
        await Support.settle(session)
        #expect(!controller.isVisible)
    }
}
