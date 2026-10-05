import Foundation
import Testing
@testable import Meraline

struct UsageTallyTests {
    @Test func talliesAddUpAndKeepTheMost() {
        var a = UsageTally()
        a.questions = 2
        a.longestChat = 5
        a.rewrites = ["shorter": 1]
        a.providers = ["anthropic": 2]
        a.games = ["rhymeDuel": .init(started: 1, roundsWon: 1)]
        var b = UsageTally()
        b.questions = 3
        b.longestChat = 3
        b.rewrites = ["shorter": 2, "longer": 1]
        b.providers = ["anthropic": 1, "codex": 1]
        b.games = ["rhymeDuel": .init(started: 1, roundsLost: 1), "categories": .init(started: 1)]
        let sum = a + b
        #expect(sum.questions == 5)
        #expect(sum.longestChat == 5, "the most, not the sum")
        #expect(sum.rewrites == ["shorter": 3, "longer": 1])
        #expect(sum.providers == ["anthropic": 3, "codex": 1])
        #expect(sum.games["rhymeDuel"] == .init(started: 2, roundsWon: 1, roundsLost: 1))
        #expect(sum.games["categories"]?.started == 1)
        #expect(sum.rounds == 2 && sum.roundsWon == 1 && sum.roundsLost == 1)
        #expect(UsageTally().isEmpty)
        #expect(!sum.isEmpty)
    }

    @Test func answersAreCountedByModelWithTheirTokensAndCost() {
        var tally = UsageTally()
        let key = UsageTally.ModelTally.key(provider: .anthropic, model: "claude-sonnet-5")
        #expect(key == "anthropic/claude-sonnet-5")
        #expect(UsageTally.ModelTally.key(provider: .claudeCode, model: " ") == "claudeCode", "an agent's default model has no name")
        #expect(UsageTally.ModelTally.provider(of: key) == .anthropic)
        #expect(UsageTally.ModelTally.model(of: key) == "claude-sonnet-5")
        #expect(UsageTally.ModelTally.model(of: "claudeCode").isEmpty)

        tally.count(answer: TokenUsage(input: 100, output: 20, cacheRead: 50, cacheWrite: 10), reported: true, for: key)
        tally.count(answer: TokenUsage(input: 30, output: 5, cost: 0.02), reported: true, for: key)
        tally.count(answer: TokenUsage(input: 40, output: 8), reported: false, for: key)
        let model = try! #require(tally.models[key])
        #expect(model.answers == 3 && model.reportedAnswers == 2 && model.costedAnswers == 1)
        #expect(model.input == 170 && model.output == 33 && model.cacheRead == 50 && model.cacheWrite == 10)
        #expect(model.cost == 0.02)
        #expect(model.unpriced == .init(input: 140, output: 28, cacheRead: 50, cacheWrite: 10), "what the provider didn't cost waits for a price")
        #expect(tally.inputTokens == 230 && tally.outputTokens == 33)
    }

    @Test func tokenUsageMergesByReplacingOrAdding() {
        let start = TokenUsage(input: 100, output: 1, cacheRead: 20)
        let delta = TokenUsage(output: 50)
        #expect(start.merging(delta, adding: false) == TokenUsage(input: 100, output: 50, cacheRead: 20), "a later report of the same answer replaces its fields")
        let step = TokenUsage(input: 10, output: 5, cost: 0.001)
        #expect(step.merging(step, adding: true) == TokenUsage(input: 20, output: 10, cost: 0.002), "steps add up")
        #expect(TokenUsage().hasTokens == false && delta.hasTokens)
        #expect(TokenUsage.zero.merging(TokenUsage(model: "gpt-5"), adding: false).model == "gpt-5")
    }

    @Test func wordsAndTokensAreEstimated() {
        #expect(UsageTally.words(in: "  What is   up\nthere ") == 4)
        #expect(UsageTally.words(in: "") == 0)
        #expect(UsageTally.estimatedTokens(in: "") == 0)
        #expect(UsageTally.estimatedTokens(in: "Hello there") == 3, "about four characters a token")
        #expect(UsageTally.estimatedTokens(in: String(repeating: "a", count: 400)) == 100)
    }
}

@MainActor
struct UsageLedgerTests {
    /// 2027-01-15 08:00 UTC, a Friday.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func ledger() -> UsageLedger {
        let ledger = UsageLedger(file: nil)
        ledger.record(at: now.addingTimeInterval(-10 * 60)) { $0.questions += 1 }
        ledger.record(at: now.addingTimeInterval(-3 * 3_600)) { $0.questions += 2 }
        ledger.record(at: now.addingTimeInterval(-2 * 24 * 3_600)) { $0.questions += 4 }
        ledger.record(at: now.addingTimeInterval(-3 * 24 * 3_600)) { $0.questions += 8 }
        ledger.record(at: now.addingTimeInterval(-20 * 24 * 3_600)) { $0.questions += 16 }
        ledger.record(at: now.addingTimeInterval(-200 * 24 * 3_600)) { $0.questions += 32 }
        ledger.record(at: now.addingTimeInterval(-400 * 24 * 3_600)) { $0.questions += 64 }
        return ledger
    }

    @Test func slotsSumIntoWindows() {
        let ledger = ledger()
        #expect(ledger.summary(.hour, now: now).questions == 1)
        #expect(ledger.summary(.day, now: now).questions == 3)
        #expect(ledger.summary(.week, now: now).questions == 15)
        #expect(ledger.summary(.month, now: now).questions == 31)
        #expect(ledger.summary(.year, now: now).questions == 63)
        #expect(ledger.allTime.questions == 127)
        #expect(UsageLedger.slot(of: now) == 6_000_000)
        #expect(UsageLedger.start(ofSlot: 6_000_000) == now, "five-minute slots, and now sits on one")
    }

    @Test func theChartsBarsFollowTheClockAndTheCalendar() {
        let ledger = ledger()
        let hour = ledger.series(.hour, now: now, calendar: utc)
        #expect(hour.count == 12)
        #expect(hour.last?.end == now && hour.first?.start == now.addingTimeInterval(-3_600))
        #expect(hour.map(\.tally.questions) == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0], "ten minutes ago opens the second-to-last five minutes")

        let day = ledger.series(.day, now: now, calendar: utc)
        #expect(day.count == 24)
        #expect(day.map(\.tally.questions).reduce(0, +) == 3)
        #expect(day[24 - 3].tally.questions == 2 || day[24 - 4].tally.questions == 2, "three hours ago")

        let week = ledger.series(.week, now: now, calendar: utc)
        #expect(week.count == 7)
        #expect(week.first?.start == utc.date(byAdding: .day, value: -6, to: utc.startOfDay(for: now)), "seven calendar days, today last")
        #expect(week.last?.start == utc.startOfDay(for: now) && week.last?.end == now)
        #expect(week.map(\.tally.questions) == [0, 0, 0, 8, 4, 0, 3])

        let year = ledger.series(.year, now: now, calendar: utc)
        #expect(year.count == 12)
        #expect(year.last?.start == utc.dateInterval(of: .month, for: now)?.start, "twelve calendar months, this one last")
        #expect(year.map(\.tally.questions).reduce(0, +) == 63)
        #expect(ledger.series(.month, now: now, calendar: utc).count == 30)
    }

    @Test func activeDaysStreaksAndBusiestHours() {
        let ledger = ledger()
        #expect(ledger.activeDays(.week, now: now, calendar: utc).count == 3)
        #expect(ledger.longestStreak(.week, now: now, calendar: utc) == 2, "three and two days ago, in a row")
        #expect(ledger.longestStreak(.hour, now: now, calendar: utc) == 1)
        #expect(UsageLedger(file: nil).longestStreak(.year, now: now, calendar: utc) == 0)
        #expect(ledger.busiestHour(.day, now: now, calendar: utc) == 5, "the two questions at 05:00 UTC beat the one at 07:50")
        #expect(ledger.busiestWeekday(.week, now: now, calendar: utc) == 3, "Tuesday, three days before a Friday, with eight")
        #expect(UsageLedger(file: nil).busiestHour(.day, now: now) == nil)
    }

    @Test func theLedgerIsKeptOnDiskAndCanBeCleared() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.\(UUID().uuidString)")
        let file = folder.appending(path: "usage.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let ledger = UsageLedger(file: file)
        ledger.record(at: now) { tally in
            tally.questions += 1
            tally.count(answer: TokenUsage(input: 12, output: 3, cost: 0.5), reported: true, for: "anthropic/claude")
            tally.games["rhymeDuel"] = .init(started: 1)
        }
        await ledger.save()
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(ledger.savedAt != nil)

        let again = UsageLedger(file: file)
        #expect(again.slots == ledger.slots, "the file holds the slots as they were")
        #expect(again.summary(.hour, now: now).models["anthropic/claude"]?.cost == 0.5)
        #expect(again.savedAt == ledger.savedAt)

        again.clear()
        #expect(again.slots.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(UsageLedger(file: file).slots.isEmpty)

        let text = try #require(String(data: JSONEncoder().encode(ledger.summary(.hour, now: now)), encoding: .utf8))
        #expect(!text.contains("claude-sonnet") && !text.contains("question text"), "counts only")
    }
}

@MainActor
struct UsageCountingTests {
    private typealias Support = GameTestSupport

    @Test func askingCountsTheQuestionAndItsAnswer() async throws {
        let usage = UsageLedger(file: nil)
        let model = ScriptedModel(["Hello there, friend", "Second"])
        let session = Support.session(model, usage: usage)
        session.draft = "What is up"
        session.send()
        var tally = usage.allTime
        #expect(tally.questions == 1 && tally.chats == 1)
        #expect(tally.wordsAsked == 3)
        #expect(tally.providers == ["custom": 1])
        #expect(tally.agentRuns == 0)
        #expect(tally.answers == 0, "not until it arrives")
        await Support.settle(session)
        tally = usage.allTime
        #expect(tally.answers == 1 && tally.failures == 0 && tally.stops == 0)
        #expect(tally.wordsRead == 3 && tally.longestAnswer == 3 && tally.longestChat == 1)
        #expect(tally.secondsWaited >= 0)
        let key = "custom/games"
        let counted = try #require(tally.models[key])
        #expect(counted.answers == 1 && counted.reportedAnswers == 0, "the scripted model reports no tokens, so they are estimated")
        #expect(counted.unpricedAnswers == 1, "and no table prices them yet")
        #expect(counted.input > 0, "the prompt and the question, at four characters a token")
        #expect(counted.output == 5, "“Hello there, friend” is 19 characters")
        #expect(counted.unpriced.output == 5 && counted.cost == 0)

        await Support.play("And now?", in: session)
        tally = usage.allTime
        #expect(tally.questions == 2 && tally.chats == 1, "a follow-up starts no chat")
        #expect(tally.longestChat == 2)
        #expect(tally.models[key]?.answers == 2)

        session.copyLastAnswer()
        #expect(usage.allTime.answersCopied == 1)
    }

    @Test func aReportedUsageCountsAsReportedWithItsCost() async throws {
        let usage = UsageLedger(file: nil)
        let took = TokenUsage(input: 120, output: 8, cacheRead: 30, cost: 0.0021, model: "served-model")
        let model = ScriptedModel(["Hello"], usage: [took])
        let session = Support.session(model, usage: usage)
        await Support.play("Hi", in: session)
        #expect(session.turns.last?.usage == took)
        let counted = try #require(usage.allTime.models["custom/served-model"], "keyed by the model the provider named")
        #expect(counted.answers == 1 && counted.reportedAnswers == 1 && counted.costedAnswers == 1)
        #expect(counted.input == 120 && counted.output == 8 && counted.cacheRead == 30)
        #expect(counted.cost == 0.0021 && counted.unpriced == .init(), "nothing left to price")
        #expect(usage.allTime.inputTokens == 150 && usage.allTime.outputTokens == 8)
    }

    @Test func askingAgainRewritingAndFailingAreCounted() async throws {
        let usage = UsageLedger(file: nil)
        let model = ScriptedModel(["First", "Again", "Shorter"])
        let session = Support.session(model, usage: usage)
        await Support.play("Tell me", in: session)
        session.askAgain()
        await Support.settle(session)
        #expect(usage.allTime.askAgains == 1 && usage.allTime.questions == 1)
        #expect(usage.allTime.answers == 2)
        session.rewrite(.shorter)
        await Support.settle(session)
        #expect(usage.allTime.rewrites == ["shorter": 1])
        #expect(usage.allTime.answers == 3 && usage.allTime.providers["custom"] == 3)

        await Support.play("One more", in: session)
        #expect(usage.allTime.failures == 1, "the scripted model had no reply left")
        #expect(usage.allTime.answers == 3)
    }

    @Test func gamesCountTheirRoundsMovesAndHints() async throws {
        let usage = UsageLedger(file: nil)
        let model = ScriptedModel(["DRAPE"])
        let session = Support.session(model, usage: usage)
        session.dice = GameDice(seed: 2)
        session.startGame(.longestWord)
        #expect(usage.allTime.games["longestWord"]?.started == 1)
        await Support.settle(session)
        #expect(usage.allTime.models["custom/games"]?.answers == 1, "the model's pick is counted")
        #expect(usage.allTime.answers == 0, "as tokens, not as an answer read")
        session.hint()
        #expect(usage.allTime.games["longestWord"]?.hints == 1)
        await Support.play("zzzzzzzz", in: session)
        #expect(usage.allTime.games["longestWord"]?.rejectedMoves == 1)
        let letters = try #require(LongestWord.letters(of: session.turns))
        let best = try #require(WordCheck.longestWords(from: letters).first)
        await Support.play(best, in: session)
        let scores = try #require(usage.allTime.games["longestWord"])
        #expect(scores.moves == 1 && scores.rejectedMoves == 1)
        #expect(scores.rounds == 1 && scores.roundsWon + scores.roundsDrawn == 1, "the best word this Mac knows wins or ties")
        #expect(usage.allTime.questions == 0, "moves are not questions")
    }
}

@MainActor
struct UsageKindTests {
    private typealias Support = GameTestSupport
    /// 2027-01-15 08:00 UTC, a Friday.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aTallyIsPartedByTheKindOfModelItCameFrom() throws {
        var tally = UsageTally()
        tally.questions = 4
        tally.chats = 2
        tally.wordsRead = 300
        tally.providers = ["anthropic": 3, "claudeCode": 1]
        tally.count(answer: TokenUsage(input: 100, output: 10, cost: 0.5), reported: true, for: "anthropic/claude-sonnet-5")
        tally.count(answer: TokenUsage(input: 900, output: 40, cost: 2), reported: true, for: "claudeCode")
        tally.count(answer: TokenUsage(input: 50, output: 1), reported: true, for: "typeSafe/jev-latest")
        tally.agentRuns = 1
        tally.toolUses = 6
        tally.decisions = 3
        tally.liveDecisions = 2
        tally.games = ["rhymeDuel": .init(started: 1, roundsWon: 1)]
        tally.answersCopied = 1

        let parts = tally.byKind()
        let llm = try #require(parts[.llm])
        let agent = try #require(parts[.agent])
        let decision = try #require(parts[.decision])
        #expect(llm.providers == ["anthropic": 3] && agent.providers == ["claudeCode": 1])
        #expect(Array(llm.models.keys) == ["anthropic/claude-sonnet-5"] && Array(agent.models.keys) == ["claudeCode"])
        #expect(Array(decision.models.keys) == ["typeSafe/jev-latest"])
        #expect(agent.agentRuns == 1 && agent.toolUses == 6 && llm.toolUses == 0, "what only agents do is the agents'")
        #expect(decision.decisions == 3 && decision.liveDecisions == 2 && llm.decisions == 0)
        #expect(llm.questions == 4 && llm.wordsRead == 300 && llm.games["rhymeDuel"]?.started == 1 && llm.answersCopied == 1,
                "what says nothing of its kind goes to the kind asked most")
        #expect(parts.values.reduce(UsageTally(), +).questions == tally.questions)
        #expect(parts.values.map { $0.cost(pricedBy: { _ in nil }).total }.reduce(0, +) == tally.cost(pricedBy: { _ in nil }).total, "no cost is lost or doubled")

        var agentOnly = UsageTally()
        agentOnly.toolUses = 2
        agentOnly.wordsRead = 40
        agentOnly.count(answer: TokenUsage(input: 10, output: 1), reported: true, for: "codex")
        #expect(Array(agentOnly.byKind().keys) == [.agent], "with no questions, the answers say whose it is")
        var unknown = UsageTally()
        unknown.answersCopied = 1
        #expect(unknown.byKind()[.llm]?.answersCopied == 1, "and with nothing to tell, the LLMs'")
        #expect(UsageTally().byKind().isEmpty)
    }

    @Test func theLedgerCountsAndShowsEachKindApart() {
        let ledger = UsageLedger(file: nil)
        ledger.record(at: now.addingTimeInterval(-60), as: .llm) { $0.questions += 2 }
        ledger.record(at: now.addingTimeInterval(-60), as: .agent) { $0.questions += 1; $0.agentRuns += 1 }
        ledger.record(at: now.addingTimeInterval(-3 * 3_600), as: .decision) { $0.questions += 5; $0.decisions += 5 }
        ledger.record(at: now.addingTimeInterval(-3 * 3_600)) { $0.count(answer: TokenUsage(input: 7, output: 1), reported: true, for: "codex") }

        #expect(ledger.summary(.day, now: now).questions == 8, "every kind unless said")
        #expect(ledger.summary(.day, now: now, kinds: [.llm]).questions == 2)
        #expect(ledger.summary(.day, now: now, kinds: [.agent, .decision]).questions == 6)
        #expect(ledger.summary(.day, now: now, kinds: [.agent]).models["codex"]?.input == 7, "a count without a kind goes by what it holds")
        #expect(ledger.summary(.hour, now: now, kinds: [.decision]).isEmpty)
        #expect(ledger.series(.day, now: now, kinds: [.decision]).map(\.tally.questions).reduce(0, +) == 5)
        #expect(ledger.activeDays(.week, now: now, kinds: [.llm]).count == 1)
        #expect(ledger.busiestHour(.day, now: now, calendar: Self.utc, kinds: [.decision]) == 5, "the decisions at 05:00 UTC")
        #expect(ledger.busiestHour(.day, now: now, calendar: Self.utc, kinds: [.llm]) == 7)
        #expect(ledger.allTime.questions == 8)

        ledger.record(at: now, as: .agent) { _ in }
        #expect(ledger.slots[UsageLedger.slot(of: now)] == nil, "nothing counted, nothing kept")
    }

    @Test func aLedgerFromBeforeKindsIsPartedAsItIsRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.\(UUID().uuidString)")
        let file = folder.appending(path: "usage.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let slot = UsageLedger.slot(of: now)
        let old = """
        {"version":1,"savedAt":0,"slots":{"\(slot)":{"questions":3,"providers":{"openAI":2,"codex":1},"agentRuns":1,"toolUses":4,\
        "decisions":2,"models":{"openAI/gpt-5":{"answers":2,"input":40,"output":9,"cost":0.25}}}}}
        """
        try Data(old.utf8).write(to: file)

        let ledger = UsageLedger(file: file)
        #expect(ledger.summary(.hour, now: now).questions == 3, "nothing lost")
        #expect(ledger.summary(.hour, now: now, kinds: [.llm]).questions == 3, "the kind asked most takes what says nothing of its kind")
        #expect(ledger.summary(.hour, now: now, kinds: [.agent]).toolUses == 4)
        #expect(ledger.summary(.hour, now: now, kinds: [.agent]).providers == ["codex": 1])
        #expect(ledger.summary(.hour, now: now, kinds: [.decision]).decisions == 2)
        #expect(ledger.summary(.hour, now: now, kinds: [.llm]).models["openAI/gpt-5"]?.cost == 0.25)

        await ledger.save()
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"version\":2"))
        #expect(UsageLedger(file: file).slots == ledger.slots, "written by kind, and read back the same")
    }

    @Test func preferencesKeepTheKindsShownAndNeverNone() {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = SecretStore(read: { _ in "" }, write: { _, _ in })
        let preferences = Preferences(defaults: defaults, secrets: secrets, onDeviceModelAvailable: false)
        #expect(preferences.usageKinds == Set(ProviderKind.allCases))
        preferences.usageKinds = [.agent]
        #expect(defaults.stringArray(forKey: "usage.kinds") == ["agent"])
        preferences.usageKinds = []
        #expect(preferences.usageKinds == [.agent], "the last kind stays")
        #expect(Preferences(defaults: defaults, secrets: secrets, onDeviceModelAvailable: false).usageKinds == [.agent])
        preferences.usageKinds = Set(ProviderKind.allCases)
        #expect(defaults.object(forKey: "usage.kinds") == nil, "only a change is kept")
    }

    @Test func aChatAndItsGameCountUnderTheirModelsKind() async throws {
        let usage = UsageLedger(file: nil)
        let session = Support.session(ScriptedModel(["Hello there", "DRAPE"]), usage: usage)
        await Support.play("What is up", in: session)
        session.copyLastAnswer()
        session.startGame(.longestWord)
        await Support.settle(session)
        let llm = usage.summary(.day, kinds: [.llm])
        #expect(llm.questions == 1 && llm.answers == 1 && llm.answersCopied == 1)
        #expect(llm.games["longestWord"]?.started == 1, "played against the LLM")
        #expect(usage.summary(.day, kinds: [.agent, .decision]).isEmpty)
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
