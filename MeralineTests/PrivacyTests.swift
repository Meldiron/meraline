import Foundation
import Testing
@testable import Meraline

@MainActor
struct PrivacyTests {
    private typealias Support = GameTestSupport

    // MARK: On this Mac

    private func settings(_ baseURL: String, model: String = "llama3.2") -> ProviderSettings {
        ProviderSettings(model: model, baseURL: baseURL, apiKey: "", isEnabled: true)
    }

    @Test func appleIntelligenceAndALocalOllamaAnswerOnThisMac() {
        #expect(settings("").answersOnThisMac(for: .apple))
        #expect(settings("http://127.0.0.1:11434").answersOnThisMac(for: .ollama))
        #expect(settings("http://localhost:11434/").answersOnThisMac(for: .ollama))
        #expect(settings("http://[::1]:11434").answersOnThisMac(for: .ollama))
        #expect(settings(" http://127.0.0.2:11434 ").answersOnThisMac(for: .ollama))
    }

    @Test func ollamasCloudModelsAndOtherMachinesDoNot() {
        #expect(!settings("http://127.0.0.1:11434", model: "gpt-oss:120b-cloud").answersOnThisMac(for: .ollama))
        #expect(!settings("http://127.0.0.1:11434", model: "glm-4.6:cloud").answersOnThisMac(for: .ollama))
        #expect(!settings("http://192.168.1.20:11434").answersOnThisMac(for: .ollama))
        #expect(!settings("http://127.example.com:11434").answersOnThisMac(for: .ollama))
        #expect(!settings("https://ollama.com").answersOnThisMac(for: .ollama))
        #expect(!settings("not a url").answersOnThisMac(for: .ollama))
    }

    @Test func aCustomServerOrACloudProviderNeverCounts() {
        #expect(!settings("http://127.0.0.1:1234/v1").answersOnThisMac(for: .custom))
        #expect(!settings("https://api.anthropic.com/v1").answersOnThisMac(for: .anthropic))
        #expect(!settings("claude").answersOnThisMac(for: .claudeCode))
    }

    @Test func thePreferencesSayWhetherTheProviderInUseIsLocal() {
        let preferences = Support.preferences()
        #expect(preferences.activeProvider == .custom)
        #expect(!preferences.answersOnThisMac)
        preferences[.ollama] = settings(Provider.ollama.defaultBaseURL)
        preferences.provider = .ollama
        #expect(preferences.answersOnThisMac)
        preferences[.ollama] = settings(Provider.ollama.defaultBaseURL, model: "qwen3-coder:480b-cloud")
        #expect(!preferences.answersOnThisMac)
    }

    @Test func theSparkleSaysWhichProvidersAreLocal() {
        let preferences = Support.preferences()
        preferences[.ollama] = settings(Provider.ollama.defaultBaseURL)
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        let menu = PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in }).providersMenu
        #expect(menu.actions.first { $0.id == "provider.ollama" }?.subtitle == "llama3.2 · on this Mac")
        #expect(menu.actions.first { $0.id == "provider.custom" }?.subtitle == "games")
    }

    // MARK: Screen sharing

    @Test func hidingFromScreenSharingIsOffUntilTurnedOnAndThenKept() {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let noSecrets = SecretStore(read: { _ in "" }, write: { _, _ in })
        let preferences = Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false)
        #expect(!preferences.hidesFromScreenSharing)
        preferences.hidesFromScreenSharing = true
        #expect(Preferences(defaults: defaults, secrets: noSecrets, onDeviceModelAvailable: false).hidesFromScreenSharing)
    }

    @Test func theSparkleTurnsHidingFromScreenSharingOnAndOff() {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        let context = PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in })
        let hide = context.providersMenu.actions.first { $0.id == "hideFromScreenSharing" }
        #expect(hide?.isChecked == false)
        hide?.perform()
        #expect(preferences.hidesFromScreenSharing)
        #expect(context.providersMenu.actions.first { $0.id == "hideFromScreenSharing" }?.isChecked == true)
    }

    // MARK: The idle clock

    @Test func theCountdownRoundsUpToWholeMinutes() {
        #expect(ForgetCountdown.text(remaining: 30 * 60) == "forgets in 30m")
        #expect(ForgetCountdown.text(remaining: 29 * 60 + 1) == "forgets in 30m")
        #expect(ForgetCountdown.text(remaining: 28 * 60) == "forgets in 28m")
        #expect(ForgetCountdown.text(remaining: 30) == "forgets in 1m")
        #expect(ForgetCountdown.text(remaining: -5) == "forgets in 1m")
        #expect(ForgetCountdown.text(remaining: 60 * 60) == "forgets in 1h")
        #expect(ForgetCountdown.text(remaining: 90 * 60) == "forgets in 1h 30m")
        #expect(ForgetCountdown.spoken(remaining: 60) == "1 minute")
        #expect(ForgetCountdown.spoken(remaining: 28 * 60) == "28 minutes")
        #expect(ForgetCountdown.spoken(remaining: 60 * 60) == "1 hour")
    }

    @Test func theCountdownChangesOnEachMinuteBeforeTheDeadline() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let deadline = start.addingTimeInterval(150)
        let entries = ForgetCountdown.Schedule(deadline: deadline).entries(from: start, mode: .normal)
        #expect(entries == [start, start.addingTimeInterval(30), start.addingTimeInterval(90), deadline])
        #expect(entries.map { ForgetCountdown.duration(remaining: deadline.timeIntervalSince($0)) } == ["3m", "2m", "1m", "1m"])
        #expect(ForgetCountdown.Schedule(deadline: nil).entries(from: start, mode: .normal) == [start])
        #expect(ForgetCountdown.Schedule(deadline: start).entries(from: start, mode: .normal) == [start])
    }

    private func chat() async -> (IdleClock, ChatSession, PanelLayout, Preferences) {
        let preferences = Support.preferences()
        let model = ScriptedModel(["Paris."])
        let session = ChatSession(preferences: preferences) { model.stream($0) }
        await Support.play("Capital of France?", in: session)
        let layout = PanelLayout()
        return (IdleClock(session: session, preferences: preferences, layout: layout), session, layout, preferences)
    }

    @Test func leavingTheWindowStartsTheClockAndComingBackStopsIt() async {
        let (clock, session, layout, _) = await chat()
        let left = Date.now
        clock.leave(at: left)
        #expect(layout.forgetsAt == left.addingTimeInterval(30 * 60))
        clock.leave(at: left.addingTimeInterval(60))
        #expect(layout.forgetsAt == left.addingTimeInterval(30 * 60), "leaving again keeps the first time")
        clock.comeBack(at: left.addingTimeInterval(29 * 60))
        #expect(layout.forgetsAt == nil)
        #expect(session.turns.count == 1)
    }

    @Test func comingBackLateStartsFresh() async {
        let (clock, session, layout, _) = await chat()
        let left = Date.now
        clock.leave(at: left)
        clock.comeBack(at: left.addingTimeInterval(30 * 60))
        #expect(session.turns.isEmpty)
        #expect(session.history.map(\.title) == ["Capital of France?"])
        #expect(layout.forgetsAt == nil)
    }

    @Test func theClockRunsOutWithoutComingBack() async {
        let (clock, session, layout, _) = await chat()
        clock.leave(at: Date.now.addingTimeInterval(-31 * 60))
        for _ in 0..<200 where !session.turns.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.turns.isEmpty)
        #expect(session.history.count == 1)
        #expect(layout.forgetsAt == nil)
    }

    @Test func anAnswerStillComingGetsTheWholeWaitOnceItArrives() async throws {
        let preferences = Support.preferences()
        let answer = AsyncThrowingStream<StreamOutput, Error>.makeStream()
        let session = ChatSession(preferences: preferences) { _ in answer.stream }
        session.draft = "Tell me a long story"
        session.send()
        let layout = PanelLayout()
        let clock = IdleClock(session: session, preferences: preferences, layout: layout)
        clock.leave(at: Date.now.addingTimeInterval(-31 * 60))
        for _ in 0..<200 where (layout.forgetsAt ?? .distantPast) < .now {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let restarted = try #require(layout.forgetsAt)
        #expect(session.turns.count == 1, "the answer still coming keeps the chat")
        try await Task.sleep(for: .milliseconds(50))
        answer.continuation.yield(.text("Once upon a time."))
        answer.continuation.finish()
        await Support.settle(session)
        for _ in 0..<200 where layout.forgetsAt == restarted {
            await Task.yield()
        }
        #expect(try #require(layout.forgetsAt) > restarted, "the clock starts over when the answer is in")
        #expect(session.turns.count == 1)
    }

    @Test func nothingCountsDownWithoutAChatOrUnderNever() async {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        let layout = PanelLayout()
        let empty = IdleClock(session: session, preferences: preferences, layout: layout)
        empty.leave()
        #expect(layout.forgetsAt == nil)

        let (clock, _, chatLayout, chatPreferences) = await chat()
        clock.leave()
        #expect(chatLayout.forgetsAt != nil)
        chatPreferences.idleReset = .never
        for _ in 0..<200 where chatLayout.forgetsAt != nil {
            await Task.yield()
        }
        #expect(chatLayout.forgetsAt == nil)
    }
}
