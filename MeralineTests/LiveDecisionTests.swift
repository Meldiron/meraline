import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Meraline

/// The decisions the Context card makes as you type in Decision mode (`LiveDecisions`): the Live switch, the
/// pause after typing and the ask that comes anyway while typing goes on, the question in the input, the ones kept
/// from it, and the presets asked at once in one request, the answers kept and shown dimmed while newer ones are
/// on their way, what a new chat starts over, the capsules on the card, and the count in the ledger.
@MainActor
struct LiveDecisionTests {
    private typealias Support = GameTestSupport

    /// Answers live asks on its own, and remembers each.
    @MainActor
    final class ScriptedDecider {
        struct Ask: Equatable {
            let questions: [DecisionQuestion]
            let texts: [String]
            let provider: Provider
        }

        private(set) var asks: [Ask] = []
        /// What a question is answered with, by its wording; Yes for any other.
        var answers: [String: Decision] = [:]
        /// What every question is answered with about a text, by the texts joined with newlines, ahead of `answers`.
        var answersByText: [String: Decision] = [:]
        var delay: Duration = .zero
        var error: Error?
        var usage = TokenUsage()

        func decide(_ questions: [DecisionQuestion], _ state: [SelectedText], _ settings: ProviderSettings, _ provider: Provider) async throws -> DecisionClient.LiveReply {
            asks.append(Ask(questions: questions, texts: state.map(\.text), provider: provider))
            if delay > .zero { try await Task.sleep(for: delay) }
            if let error { throw error }
            var decisions: [String: Decision] = [:]
            let about = state.map(\.text).joined(separator: "\n")
            for question in questions { decisions[question.id] = answersByText[about] ?? answers[question.question] ?? LiveDecisionTests.yes }
            return DecisionClient.LiveReply(decisions: decisions, usage: usage)
        }
    }

    static let yes = Decision(options: [.init(label: "Yes", probability: 0.91), .init(label: "No", probability: 0.09)], isYesNo: true, confidence: 0.82)
    static let no = Decision(options: [.init(label: "Yes", probability: 0.2), .init(label: "No", probability: 0.8)], isYesNo: true, confidence: 0.6)
    static let neutral = Decision(options: [.init(label: "Friendly", probability: 0.2), .init(label: "Neutral", probability: 0.7), .init(label: "Angry", probability: 0.1)], confidence: 0.7)

    /// A session in Decision mode with TypeSafe ready and short waits, deciding live through `decider`.
    private static func session(_ decider: ScriptedDecider, live: Bool = true) -> (session: ChatSession, preferences: Preferences) {
        let preferences = Support.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        preferences.mode = .decision
        let model = ScriptedModel()
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { model.stream($0) }, decideLive: decider.decide)
        session.liveDecisions.isOn = live
        session.liveDecisions.debounce = 0.04
        session.liveDecisions.maxWait = 0.12
        return (session, preferences)
    }

    /// Waits out the pause and any ask on its way.
    private static func settle(_ session: ChatSession) async {
        try? await Task.sleep(for: .milliseconds(100))
        for _ in 0..<2_000 {
            guard !session.liveDecisions.pending.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func theCardDecidesAsYouTypeAfterAPause() async throws {
        let decider = ScriptedDecider()
        let (session, _) = Self.session(decider)
        session.writeState()
        session.draft = "Is this urgent?"
        let live = session.liveDecisions
        #expect(live.questions.map(\.id) == ["input", "preset.urgent", "preset.scam", "preset.tone", "preset.priority"], "the input's question, then every preset")
        #expect(live.questions.map(\.isOn) == [true, false, false, false, false])
        #expect(live.pending.isEmpty, "nothing to decide about yet")
        #expect(!live.asksNothing)

        session.typedState = "Production is d"
        #expect(live.pending == ["input"])
        session.typedState = "Production is down"
        #expect(decider.asks.isEmpty, "not before the pause")
        await Self.settle(session)
        #expect(decider.asks.count == 1, "one ask after the pause, not one a letter")
        #expect(decider.asks.last?.questions == [DecisionQuestion(id: "input", question: "Is this urgent?", answers: .yesNo)])
        #expect(decider.asks.last?.texts == ["Production is down"])
        #expect(decider.asks.last?.provider == .typeSafe)
        let input = try #require(live.questions.first)
        #expect(live.answer(for: input) == Self.yes)
        #expect(live.pending.isEmpty && live.failure == nil && !live.isStale(input))
        #expect(session.turns.isEmpty, "no turn in the chat")
        #expect(session.draft == "Is this urgent?" && session.typedState == "Production is down", "nothing of the draft goes")

        // Counted as decisions, and as live ones, never as questions or answers of the chat.
        let tally = session.usage.summary(.day)
        #expect(tally.decisions == 1 && tally.liveDecisions == 1 && tally.unsureDecisions == 0)
        #expect(tally.questions == 0 && tally.answers == 0)
        #expect(tally.models.keys.contains { $0.hasPrefix("typeSafe") }, "the model's tokens are counted")
        let data = try JSONEncoder().encode(tally)
        #expect(try JSONDecoder().decode(UsageTally.self, from: data).liveDecisions == 1, "and kept in the ledger's file")

        // More typing asks again; the last answer stays until the new one comes, so the capsule never goes blank,
        // and the Live switch shows the loader meanwhile.
        session.typedState = "Production is down!"
        #expect(live.answer(for: input) == Self.yes)
        #expect(live.isPending(input) && live.isStale(input) && live.isWorking)
        await Self.settle(session)
        #expect(decider.asks.count == 2)
        #expect(decider.asks.last?.texts == ["Production is down!"])
        #expect(live.answer(for: input) == Self.yes && !live.isStale(input) && !live.isWorking)

        // A changed question too, about the same text.
        session.draft = "Is this spam?"
        #expect(live.isStale(live.questions[0]))
        await Self.settle(session)
        #expect(decider.asks.last?.questions.map(\.question) == ["Is this spam?"])

        // A text that is only spacing is nothing to decide about, and no earlier answer lingers over it.
        session.typedState = "  \n"
        #expect(live.pending.isEmpty)
        #expect(live.answer(for: live.questions[0]) == nil)
        await Self.settle(session)
        #expect(decider.asks.count == 3)

        // Return asks in the chat as ever, and the card goes with the strip.
        session.typedState = "Production is down"
        session.send()
        #expect(session.typedState == nil)
        #expect(live.questions.isEmpty && live.answers.isEmpty)
        await Support.settle(session)
        await Self.settle(session)
        #expect(decider.asks.count == 3, "nothing more asked live")
    }

    @Test func typingWithoutAPauseStillAsksOnceInAWhile() async throws {
        let decider = ScriptedDecider()
        let (session, _) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.draft = "Urgent?"
        // Typed faster than the pause, for longer than the longest wait: the asks come anyway.
        var text = ""
        for letter in "The server room is on fire and" {
            text.append(letter)
            session.typedState = text
            try await Task.sleep(for: .milliseconds(12))
        }
        #expect(decider.asks.count >= 2, "asked while the typing went on: \(decider.asks.count) ask(s)")
        #expect(decider.asks.allSatisfy { !$0.texts[0].isEmpty && text.hasPrefix($0.texts[0]) })
        let input = try #require(live.questions.first)
        #expect(live.answer(for: input) != nil, "an answer about an earlier text shows meanwhile")
        #expect(live.isStale(input) || !live.isPending(input))
        await Self.settle(session)
        #expect(decider.asks.last?.texts == [text], "and the text as it ended is asked last")
        #expect(!live.isStale(input) && !live.isPending(input))
    }

    @Test func presetsAreAskedTogetherAndOnlyWhatChangedIsAskedAgain() async throws {
        let decider = ScriptedDecider()
        decider.answers["What is the tone of this text?"] = Self.neutral
        decider.answers["Is this a scam, spam, or phishing?"] = Self.no
        let (session, _) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.typedState = "Hi team, the checkout is down."
        session.draft = "Ready to send?"
        await Self.settle(session)
        #expect(decider.asks.count == 1)
        #expect(decider.asks.last?.questions.map(\.id) == ["input"])

        // A preset turned on is asked at once, alone: the input's answer stays.
        session.toggleLivePreset("urgent")
        #expect(live.enabledPresets == ["urgent"])
        #expect(live.pending == ["preset.urgent"])
        #expect(live.answer(for: live.questions[0]) == Self.yes, "the input's answer stays")
        await Self.settle(session)
        #expect(decider.asks.count == 2)
        #expect(decider.asks.last?.questions == [DecisionQuestion(id: "preset.urgent", question: "Is this urgent?", answers: .yesNo)])
        session.toggleLivePreset("tone")
        await Self.settle(session)
        let tone = try #require(live.questions.first { $0.presetID == "tone" })
        #expect(decider.asks.last?.questions == [DecisionQuestion(id: "preset.tone", question: "What is the tone of this text?", answers: DecisionAnswers(options: ["Friendly", "Neutral", "Angry"], isOrdered: false))])
        #expect(live.answer(for: tone) == Self.neutral)
        #expect(session.usage.summary(.day).liveDecisions == 3)

        // The text changing asks every question that is on, in one request.
        session.typedState = "Hi team, the checkout is down. Fixing it."
        #expect(live.pending == ["input", "preset.urgent", "preset.tone"])
        await Self.settle(session)
        #expect(decider.asks.count == 4)
        #expect(decider.asks.last?.questions.map(\.id) == ["input", "preset.urgent", "preset.tone"])
        #expect(live.questions.map(\.isOn) == [true, true, false, true, false])

        // Off and on again asks nothing while the text stays: the answer was kept.
        session.toggleLivePreset("tone")
        #expect(live.answer(for: live.questions.first { $0.presetID == "tone" }!) == nil, "an off preset shows no answer")
        session.toggleLivePreset("tone")
        #expect(live.pending.isEmpty)
        #expect(live.answer(for: tone) == Self.neutral)
        await Self.settle(session)
        #expect(decider.asks.count == 4)

        // A preset's question in the input is asked once, and both capsules get the answer.
        session.draft = "Is this a scam, spam, or phishing?"
        session.toggleLivePreset("scam")
        session.typedState = "Everything is fine."
        await Self.settle(session)
        #expect(decider.asks.last?.questions.map(\.id) == ["input", "preset.urgent", "preset.tone"], "the scam preset is the input's question")
        #expect(live.answer(for: live.questions[0]) == Self.no)
        #expect(live.answer(for: live.questions.first { $0.presetID == "scam" }!) == Self.no)
        #expect(live.pending.isEmpty)
    }

    @Test func questionsKeptFromTheInputStayInTheirPlaceBesideThePresets() async throws {
        let decider = ScriptedDecider()
        decider.answers["Is it polite?"] = Self.no
        let (session, _) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.typedState = "Send me the file now."
        session.draft = "Is it polite?"
        await Self.settle(session)
        #expect(decider.asks.count == 1)
        #expect(live.answer(for: live.questions[0]) == Self.no)

        // The plus on the input's capsule: the question is kept, the input empties, and the answer goes with it.
        session.keepLiveQuestion()
        #expect(session.draft.isEmpty)
        #expect(live.keptQuestions.map(\.text) == ["Is it polite?"])
        let kept = try #require(live.questions.first)
        #expect(kept.keptID == live.keptQuestions[0].id && kept.id == "kept.\(live.keptQuestions[0].id.uuidString)")
        #expect(kept.title == "Is it polite?" && kept.isOn && kept.presetID == nil)
        #expect(!live.questions.contains { $0.source == .input }, "the input is empty, so it has no capsule")
        #expect(live.answer(for: kept) == Self.no, "the input's answer carries over")
        #expect(live.pending.isEmpty)
        await Self.settle(session)
        #expect(decider.asks.count == 1, "nothing asked again")

        // The input's capsule comes after the kept ones, so keeping it leaves it where it is and moves no other.
        session.draft = "Does it say thank you?"
        #expect(live.questions.map(\.id).prefix(2) == [kept.id, "input"])
        session.keepLiveQuestion()
        #expect(live.questions.map(\.id).prefix(2) == [kept.id, "kept.\(live.keptQuestions[1].id.uuidString)"], "the new one takes the input's place")
        session.toggleLivePreset("urgent")
        await Self.settle(session)
        #expect(decider.asks.last?.questions.map(\.question) == ["Does it say thank you?", "Is this urgent?"])
        session.typedState = "Send me the file now, please."
        await Self.settle(session)
        #expect(decider.asks.last?.questions.map(\.question) == ["Is it polite?", "Does it say thank you?", "Is this urgent?"])
        #expect(session.usage.summary(.day).liveDecisions == 6)

        // Off and on keeps the answer; the cross removes.
        let second = live.keptQuestions[1]
        session.toggleLiveQuestion(second.id)
        #expect(live.keptQuestions[1].isOn == false)
        #expect(live.answer(for: live.questions[1]) == nil)
        session.toggleLiveQuestion(second.id)
        #expect(live.answer(for: live.questions[1]) == Self.yes, "kept while off")
        session.removeLiveQuestion(second.id)
        #expect(live.keptQuestions.count == 1)
        #expect(!live.questions.contains { $0.keptID == second.id })

        // Keeping the same question again turns it on rather than doubling it; an empty input keeps nothing.
        session.toggleLiveQuestion(live.keptQuestions[0].id)
        #expect(!live.keptQuestions[0].isOn)
        session.draft = "Is it polite?"
        session.keepLiveQuestion()
        #expect(live.keptQuestions.count == 1 && live.keptQuestions[0].isOn)
        session.keepLiveQuestion()
        #expect(live.keptQuestions.count == 1)
    }

    @Test func anAskOvertakenByTypingStillShowsUntilTheNextComes() async throws {
        let decider = ScriptedDecider()
        decider.delay = .milliseconds(150)
        let (session, _) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.draft = "Urgent?"
        session.typedState = "First"
        try await Task.sleep(for: .milliseconds(80))
        #expect(decider.asks.count == 1, "on its way")
        session.typedState = "First draft"
        try await Task.sleep(for: .milliseconds(140))
        let input = try #require(live.questions.first)
        #expect(decider.asks.count == 2, "the next waits behind the one in flight, then goes")
        #expect(live.answer(for: input) == Self.yes && live.isStale(input), "the answer about “First” shows, dimmed, meanwhile")
        await Self.settle(session)
        #expect(decider.asks.map(\.texts) == [["First"], ["First draft"]])
        #expect(live.answer(for: input) == Self.yes && !live.isStale(input))
        #expect(session.usage.summary(.day).liveDecisions == 2, "both replies came, and cost")
    }

    @Test func theSwitchIsOffUntilTurnedOnAndClearsTheCardWhenOff() async throws {
        let decider = ScriptedDecider()
        let (session, preferences) = Self.session(decider, live: false)
        let live = session.liveDecisions
        #expect(!live.isOn)
        session.writeState()
        session.draft = "Urgent?"
        session.typedState = "Down"
        await Self.settle(session)
        #expect(decider.asks.isEmpty && live.questions.isEmpty, "off, the card shows no capsules and asks nothing")

        session.toggleLiveDecisions()
        #expect(live.isOn)
        #expect(live.pending == ["input"])
        await Self.settle(session)
        #expect(decider.asks.count == 1)
        session.toggleLiveDecisions()
        #expect(live.questions.isEmpty && live.answers.isEmpty && live.pending.isEmpty, "off again, the capsules go")

        // Only Decision mode decides live; the switch stays as it was for the chat.
        session.toggleLiveDecisions()
        await Self.settle(session)
        #expect(decider.asks.count == 2)
        preferences.mode = .llm
        session.refreshLiveDecisions()
        #expect(live.questions.isEmpty)
        #expect(live.isOn)
        preferences.mode = .decision
        session.refreshLiveDecisions()
        #expect(live.pending == ["input"])
        await Self.settle(session)
        #expect(decider.asks.count == 3)

        // The card's cross takes the strip with it; a new card starts over.
        session.removeTypedState()
        #expect(live.questions.isEmpty)
        session.writeState()
        #expect(live.questions.map(\.id).first == "input")
        #expect(live.pending.isEmpty, "an empty card has nothing to decide about")
        #expect(!live.asksNothing)
        session.draft = ""
        #expect(live.asksNothing, "no question in the input and no preset on")
    }

    @Test func aNewChatAndTheSwitchStartOverWithNothingOn() async throws {
        let decider = ScriptedDecider()
        let (session, _) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.typedState = "Send me the file now."
        session.draft = "Is it polite?"
        session.keepLiveQuestion()
        session.draft = "Is it short?"
        session.toggleLivePreset("urgent")
        session.toggleLivePreset("tone")
        await Self.settle(session)
        #expect(live.keptQuestions.count == 1 && live.enabledPresets == ["urgent", "tone"])

        // The switch turned, either way: no preset on and no kept question, the question in the input aside.
        session.toggleLiveDecisions()
        #expect(!live.isOn && live.enabledPresets.isEmpty && live.keptQuestions.isEmpty)
        #expect(session.draft == "Is it short?" && session.typedState == "Send me the file now.", "the draft is untouched")
        session.toggleLiveDecisions()
        #expect(live.isOn && live.enabledPresets.isEmpty && live.keptQuestions.isEmpty)
        #expect(live.questions.map(\.isOn) == [true, false, false, false, false])
        session.toggleLivePreset("scam")
        session.draft = "Is it polite?"
        session.keepLiveQuestion()
        await Self.settle(session)

        // A new chat, as Esc or ⌘N starts one: the switch off, nothing on, nothing kept, and the card closed, the
        // draft waiting in Recent Chats.
        #expect(session.reset())
        #expect(!live.isOn && live.enabledPresets.isEmpty && live.keptQuestions.isEmpty)
        #expect(live.questions.isEmpty && live.answers.isEmpty && live.pending.isEmpty)
        #expect(session.typedState == nil && session.draft.isEmpty)
        #expect(session.history.first?.isStash == true)
        session.writeState()
        session.draft = "Urgent?"
        session.typedState = "Down"
        await Self.settle(session)
        #expect(live.questions.isEmpty, "off until turned on again")
        let asked = decider.asks.count
        session.toggleLiveDecisions()
        await Self.settle(session)
        #expect(decider.asks.count == asked + 1 && live.questions.map(\.isOn) == [true, false, false, false, false])

        // Forgetting every chat starts over the same way.
        session.toggleLivePreset("urgent")
        _ = session.forgetAll()
        #expect(!live.isOn && live.enabledPresets.isEmpty && live.questions.isEmpty)
    }

    @Test func escapingAnEmptyChatStashesTheLiveDraftAndReopeningBringsItAllBack() async throws {
        let decider = ScriptedDecider()
        let (session, preferences) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.typedState = "Send me the file now."
        session.draft = "Is it polite?"
        session.keepLiveQuestion()
        session.draft = "Is it short?"
        session.toggleLivePreset("tone")
        await Self.settle(session)
        let asked = decider.asks.count
        let answers = live.answers
        #expect(answers.count == 3)

        // Esc pressed by habit starts a new chat, and the draft waits in Recent Chats with all of it.
        #expect(session.reset(), "stashed on its own")
        #expect(!live.isOn && live.keptQuestions.isEmpty && session.typedState == nil && session.draft.isEmpty)
        let stash = try #require(session.history.first)
        #expect(session.history.count == 1 && stash.isStash)
        #expect(stash.title == "Is it short?")
        #expect(stash.draft?.typedState == "Send me the file now.")
        #expect(stash.draft?.live?.keptQuestions.map(\.text) == ["Is it polite?"])
        #expect(stash.draft?.live?.enabledPresets == ["tone"])
        let context = PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in })
        #expect(context.historyMenu.actions.first?.subtitle == "Stashed draft")

        // Reopened from another mode, it comes back in Decision mode with Live on, its questions, and their
        // answers, which aren't asked again.
        preferences.mode = .llm
        session.reopen(stash.id)
        #expect(preferences.mode == .decision)
        #expect(session.draft == "Is it short?" && session.typedState == "Send me the file now.")
        #expect(live.isOn && live.enabledPresets == ["tone"] && live.keptQuestions.map(\.text) == ["Is it polite?"])
        #expect(live.questions.filter(\.isOn).map(\.title) == ["Is it polite?", "Is it short?", "Tone"])
        #expect(live.answers == answers && live.pending.isEmpty)
        await Self.settle(session)
        #expect(decider.asks.count == asked, "the answers came back with the draft")
        #expect(session.expiresAt == nil, "what is typed has no time of its own")
        #expect(session.history.isEmpty)

        // Typing on asks again as ever.
        session.typedState = "Send me the file now, please."
        await Self.settle(session)
        #expect(decider.asks.count == asked + 1)
        #expect(decider.asks.last?.questions.map(\.question) == ["Is it polite?", "Is it short?", "What is the tone of this text?"])
    }

    @Test func aChatTakesItsLiveDraftToRecentChats() async throws {
        let decider = ScriptedDecider()
        let (session, preferences) = Self.session(decider)
        let live = session.liveDecisions
        session.reopen(ChatSession.PastChat(turns: [Support.turn("Urgent?", reply: "Yes (82% confident)")], date: .now))
        let expiresAt = try #require(session.expiresAt)
        session.toggleLiveDecisions()
        session.writeState()
        session.typedState = "The build is red."
        session.draft = "Blocking?"
        await Self.settle(session)
        let asked = decider.asks.count

        // ⌘N or Esc: the chat goes to Recent Chats as ever, its draft with it rather than on its own.
        #expect(!session.reset(), "not on its own")
        let chat = try #require(session.history.first)
        #expect(session.history.count == 1 && !chat.isStash)
        #expect(chat.title == "Urgent?")
        #expect(chat.expiresAt == expiresAt)
        #expect(chat.draft?.text == "Blocking?" && chat.draft?.typedState == "The build is red." && chat.draft?.live != nil)
        let context = PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in })
        #expect(context.historyMenu.actions.first?.subtitle == "With a draft")

        session.reopen(chat.id)
        #expect(session.turns.map(\.question) == ["Urgent?"])
        #expect(session.expiresAt == expiresAt, "the chat keeps the time it had left")
        #expect(session.draft == "Blocking?" && session.typedState == "The build is red." && live.isOn)
        await Self.settle(session)
        #expect(decider.asks.count == asked)

        // When the chat runs out of time, what is typed stays for a new chat, the card and Live included.
        session.expireChats(now: expiresAt.addingTimeInterval(1))
        #expect(session.turns.isEmpty && session.history.isEmpty)
        #expect(session.draft == "Blocking?" && session.typedState == "The build is red." && live.isOn)
        await Self.settle(session)
        #expect(decider.asks.count == asked, "and its answers")
    }

    @Test func onlyLiveWorkIsKeptAndNeverAnonymouslyOrWhenDeleted() async throws {
        let decider = ScriptedDecider()
        let (session, _) = Self.session(decider, live: false)
        session.writeState()
        session.typedState = "Send me the file now."
        session.draft = "Is it polite?"

        // With Live off, a new chat clears the draft as it always has.
        #expect(!session.reset())
        #expect(session.history.isEmpty)

        // Nor with nothing typed: the switch alone and a preset on are nothing to lose.
        session.toggleLiveDecisions()
        session.toggleLivePreset("urgent")
        #expect(!session.reset())
        #expect(session.history.isEmpty)

        // Anonymous mode keeps it out of Recent Chats.
        session.isAnonymous = true
        session.toggleLiveDecisions()
        session.writeState()
        session.typedState = "Send me the file now."
        #expect(!session.reset())
        #expect(session.history.isEmpty)
        session.isAnonymous = false

        // Delete Chat and forgetting every chat mean it.
        session.toggleLiveDecisions()
        session.writeState()
        session.typedState = "Send me the file now."
        session.deleteChat()
        #expect(session.history.isEmpty && session.typedState == nil)
        session.toggleLiveDecisions()
        session.writeState()
        session.typedState = "Send me the file now."
        session.forgetAll()
        #expect(session.history.isEmpty && session.typedState == nil)
    }

    @Test func stashingTheDraftTakesLiveWithIt() async throws {
        let decider = ScriptedDecider()
        let (session, _) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.draft = "Is it polite?"
        session.keepLiveQuestion()
        #expect(session.canStashDraft, "a kept question is something to stash")

        session.stashDraft()
        #expect(!live.isOn && live.keptQuestions.isEmpty, "the empty chat starts with Live off")
        let stash = try #require(session.history.first)
        #expect(stash.title == "Is it polite?", "named by its kept question")
        session.reopen(stash.id)
        #expect(live.isOn && live.keptQuestions.map(\.text) == ["Is it polite?"] && session.typedState == "")
    }

    @Test func aSelectionOrTheClipboardIsDecidedAboutToo() async throws {
        let decider = ScriptedDecider()
        let (session, _) = Self.session(decider)
        session.draft = "Urgent?"
        session.bring(try #require(SelectedText("Server room is on fire", appName: "Mail")))
        session.writeState()
        await Self.settle(session)
        #expect(decider.asks.count == 1)
        #expect(decider.asks.last?.texts == ["Server room is on fire"], "the texts Return would decide about")
        session.typedState = "Also the kitchen"
        await Self.settle(session)
        #expect(decider.asks.last?.texts == ["Server room is on fire", "Also the kitchen"])
    }

    @Test func aFailureShowsOnTheCardAndCountsNothing() async throws {
        let decider = ScriptedDecider()
        decider.error = LLMError.http(401, "Invalid API key")
        let (session, _) = Self.session(decider)
        let live = session.liveDecisions
        session.writeState()
        session.draft = "Urgent?"
        session.typedState = "Down"
        await Self.settle(session)
        #expect(decider.asks.count == 1)
        #expect(live.pending.isEmpty)
        #expect(live.failure?.contains("401") == true || live.failure?.contains("Invalid API key") == true)
        #expect(live.answer(for: live.questions[0]) == nil)
        #expect(session.usage.summary(.day).liveDecisions == 0)
        #expect(session.failure == nil, "the chat's failure row stays quiet")
        // The next change asks again.
        decider.error = nil
        session.typedState = "Down again"
        #expect(live.failure == nil)
        await Self.settle(session)
        #expect(live.answer(for: live.questions[0]) == Self.yes)
    }

    @Test func severalQuestionsGoInOneRequestEightAtATimeForOllama() throws {
        let questions = (0..<10).map { DecisionQuestion(id: "q\($0)", question: "Question \($0)?", answers: .yesNo) }
        #expect(DecisionClient.batches(of: questions, for: .typeSafe).map(\.count) == [10])
        #expect(DecisionClient.batches(of: questions, for: .openRouterDecision).map(\.count) == [10])
        #expect(DecisionClient.batches(of: questions, for: .ollamaDecision).map(\.count) == [8, 2])
        #expect(DecisionClient.batches(of: [], for: .typeSafe).isEmpty)

        let state = [try #require(SelectedText("Production is down.", appName: "Mail"))]
        let settings = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        let asked = [
            DecisionQuestion(id: "input", question: "Is this urgent?", answers: .yesNo),
            DecisionQuestion(id: "preset.tone", question: "What is the tone?", answers: DecisionAnswers(options: ["Friendly", "Neutral", "Angry"], isOrdered: false)),
            DecisionQuestion(id: "preset.priority", question: "How high a priority?", answers: DecisionAnswers(options: ["Low", "Medium", "High"], isOrdered: true)),
        ]
        let request = try DecisionClient.urlRequest(asked, about: state, settings: settings)
        #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let sentBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(body["model"] as? String == "jev-latest")
        let sentState = try #require(body["state"] as? [String: Any])
        #expect(sentState["text"] as? String == "Production is down." && sentState["from"] as? String == "Mail")
        let sent = try #require(body["questions"] as? [String: [String: Any]])
        #expect(Set(sent.keys) == ["input", "preset.tone", "preset.priority"])
        #expect(sent["input"]?["type"] as? String == "noul" && sent["input"]?["instructions"] as? String == "Is this urgent?")
        #expect(sent["preset.tone"]?["type"] as? String == "choice")
        let criteria = try #require(sent["preset.tone"]?["criteria"] as? [String: Any])
        #expect(Set(criteria.keys) == ["Friendly", "Neutral", "Angry"])
        #expect(sent["preset.priority"]?["type"] as? String == "score" && sent["preset.priority"]?["criteria"] as? [String] == ["Low", "Medium", "High"])
        #expect(throws: (any Error).self, "no text, nothing to decide about") {
            try DecisionClient.urlRequest(asked, about: [], settings: settings)
        }

        let json = """
        {"model":"jev-1.13","answers":{
          "input":{"type":"noul","noul":0.91},
          "preset.tone":{"type":"choice","choice":"Neutral","confidence":0.7,"probabilities":{"Friendly":0.2,"Neutral":0.7,"Angry":0.1}},
          "preset.priority":{"type":"score","score":1.72,"confidence":0.76,"probabilities":{"0":0.04,"1":0.2,"2":0.76}}
        },"usage":{"input_tokens":40,"output_tokens":3}}
        """
        let reply = try DecisionClient.decodeLive(Data(json.utf8), for: asked)
        #expect(reply.decisions["input"]?.chosen.label == "Yes")
        #expect(abs((reply.decisions["input"]?.confidence ?? 0) - 0.82) < 1e-9)
        #expect(reply.decisions["preset.tone"]?.chosen.label == "Neutral" && reply.decisions["preset.tone"]?.confidence == 0.7)
        #expect(reply.decisions["preset.priority"]?.chosen.label == "High" && reply.decisions["preset.priority"]?.score == 1.72 && reply.decisions["preset.priority"]?.isOrdered == true)
        #expect(reply.usage.input == 40 && reply.usage.output == 3 && reply.usage.model == "jev-1.13")
        #expect(throws: (any Error).self, "a question the model skipped fails the reply") {
            try DecisionClient.decodeLive(Data(json.utf8), for: asked + [DecisionQuestion(id: "more", question: "More?", answers: .yesNo)])
        }
    }

    @Test func aLiveQuestionReadsItsAnswersAndWearsThePresetsTitle() throws {
        #expect(LiveQuestion.input("  ", fallback: .yesNo) == nil)
        let input = try #require(LiveQuestion.input("Which team? Billing / Sales", fallback: .yesNo))
        #expect(input.id == "input" && input.source == .input && input.presetID == nil && input.keptID == nil)
        #expect(input.question == "Which team?" && input.title == "Which team?" && input.answers.options == ["Billing", "Sales"])
        #expect(input.isOn)
        #expect(input.decisionQuestion == DecisionQuestion(id: "input", question: "Which team?", answers: DecisionAnswers(options: ["Billing", "Sales"], isOrdered: false)))
        let levels = DecisionAnswers(options: ["Low", "High"], isOrdered: true)
        #expect(LiveQuestion.input("Urgent?", fallback: levels)?.answers == levels, "Settings' answers for a question that names none")

        let priority = try #require(PromptPreset.decisionDefaults.first { $0.id == "priority" })
        let question = try #require(LiveQuestion.preset(priority, isOn: false, fallback: .yesNo))
        #expect(question.id == "preset.priority" && question.presetID == "priority")
        #expect(question.title == "Priority" && !question.isOn)
        #expect(question.question == "How high a priority is this?" && question.answers.isOrdered && question.answers.options == ["Low", "Medium", "High"])
        #expect(LiveQuestion.preset(PromptPreset.blank(), isOn: true, fallback: .yesNo) == nil, "a preset with no text asks nothing")
        var untitled = priority
        untitled.title = " "
        #expect(LiveQuestion.preset(untitled, isOn: true, fallback: .yesNo)?.title == "How high a priority is this?", "the question stands in for a missing title")

        let kept = KeptQuestion(id: UUID(), text: "Is it polite? Yes / No / Rude", isOn: false)
        let keptQuestion = try #require(LiveQuestion.kept(kept, fallback: .yesNo))
        #expect(keptQuestion.keptID == kept.id && keptQuestion.question == "Is it polite?" && keptQuestion.answers.options == ["Yes", "No", "Rude"] && !keptQuestion.isOn)
    }

    /// The strip lays out on the card: with Live on and answers in, the card is taller than without.
    @Test func theCardShowsTheCapsulesWhileLiveIsOn() async throws {
        let decider = ScriptedDecider()
        decider.answers["What is the tone of this text?"] = Self.neutral
        let (session, preferences) = Self.session(decider)
        session.writeState()
        session.draft = "Ready to send?"
        session.toggleLivePreset("tone")
        session.typedState = "Hi team, the checkout is down."
        await Self.settle(session)
        let live = session.liveDecisions
        #expect(live.answers.count == 2)

        func height(live: LiveDecisions?) async throws -> CGFloat {
            var text = session.typedState ?? ""
            let binding = Binding(get: { text }, set: { text = $0 })
            let focus = FocusState<Bool>()
            let card = TypedStateCard(text: binding, isDeciding: true, live: live, unsureBelow: preferences.unsureBelow, isFocused: focus.projectedValue, remove: {})
            let host = NSHostingView(rootView: card.frame(width: 600))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
        let with = try await height(live: live)
        let without = try await height(live: nil)
        #expect(with > without + 20, "the strip takes a row: \(with) against \(without)")
        live.isOn = false
        session.refreshLiveDecisions()
        let off = try await height(live: live)
        #expect(abs(off - without) < 1, "off, only the switch stays in the header: \(off) against \(without)")
    }
}
