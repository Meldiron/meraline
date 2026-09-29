import Foundation
import Testing
@testable import Meraline

/// The capsules under the empty panel that say what LLMs and agents have cost today.
@MainActor
struct CostNudgeTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Friday, 15 January 2027, 08:00 UTC, on a slot's start.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static let sonnet = UsageTally.ModelTally.key(provider: .anthropic, model: "claude-sonnet-5")
    private static let gpt = UsageTally.ModelTally.key(provider: .openRouter, model: "openai/gpt-5-mini")
    private static let claudeCode = UsageTally.ModelTally.key(provider: .claudeCode, model: "")
    private static let codex = UsageTally.ModelTally.key(provider: .codex, model: "gpt-5-codex")

    private func spend(_ cost: Double, on key: String, at date: Date, in ledger: UsageLedger) {
        ledger.record(at: date) { $0.count(answer: TokenUsage(input: 100, output: 10, cost: cost), reported: true, for: key) }
    }

    @Test func aTallySplitsItsCostIntoLLMsAndAgents() {
        var tally = UsageTally()
        tally.count(answer: TokenUsage(input: 10, output: 10, cost: 0.5), reported: true, for: Self.sonnet)
        tally.count(answer: TokenUsage(input: 1_000, output: 0), reported: true, for: Self.gpt)
        tally.count(answer: TokenUsage(input: 10, output: 10, cost: 2), reported: true, for: Self.claudeCode)
        tally.count(answer: TokenUsage(input: 0, output: 1_000), reported: true, for: Self.codex)
        let price = ModelPrice(prompt: 0.001, completion: 0.002)
        let priced: (String) -> ModelPrice? = { $0 == Self.gpt || $0 == Self.codex ? price : nil }
        #expect(abs(tally.cost(of: .llm, pricedBy: priced) - 1.5) < 1e-9, "Anthropic's reported cost, and OpenRouter's tokens at today's price")
        #expect(abs(tally.cost(of: .agent, pricedBy: priced) - 4) < 1e-9, "Claude Code's reported cost, and Codex's tokens at today's price")
        #expect(abs(tally.cost(of: .llm, pricedBy: priced) + tally.cost(of: .agent, pricedBy: priced) - tally.cost(pricedBy: priced).total) < 1e-9)
        #expect(UsageTally().cost(of: .agent) { _ in nil } == 0)
    }

    @Test func todaysCostIsTheCalendarDaysOnly() {
        let ledger = UsageLedger(file: nil)
        let midnight = utc.startOfDay(for: now)
        spend(1, on: Self.sonnet, at: now, in: ledger)
        spend(0.25, on: Self.sonnet, at: midnight, in: ledger)
        spend(5, on: Self.sonnet, at: midnight.addingTimeInterval(-60), in: ledger)
        spend(3, on: Self.claudeCode, at: now, in: ledger)
        #expect(ledger.cost(of: .llm, onDayOf: now, calendar: utc) == 1.25, "from midnight on, not the last 24 hours")
        #expect(ledger.cost(of: .agent, onDayOf: now, calendar: utc) == 3)
        #expect(ledger.cost(of: .llm, onDayOf: midnight.addingTimeInterval(-1), calendar: utc) == 5, "a minute before midnight was yesterday")
        #expect(ledger.cost(of: .agent, onDayOf: midnight.addingTimeInterval(-1), calendar: utc) == 0)
    }

    @Test func aShortSpanLooksUpItsOwnSlotsAndAddsUpTheSame() {
        let ledger = UsageLedger(file: nil)
        let noon = utc.startOfDay(for: now).addingTimeInterval(12 * 3_600)
        for day in 0..<400 {
            ledger.record(at: noon.addingTimeInterval(TimeInterval(-day) * 24 * 3_600)) { $0.questions += 1 }
        }
        #expect(ledger.slots.count == 400)
        #expect(ledger.summary(.day, now: now).questions == 1, "yesterday noon, looked up slot by slot")
        #expect(ledger.summary(.week, now: now).questions == 7)
        #expect(ledger.summary(.year, now: now).questions == 365, "through every slot kept")
        #expect(ledger.summary(from: now, to: now.addingTimeInterval(-1)).questions == 0, "a span that ends before it starts has nothing")
    }

    @Test func oneCapsuleSaysNothingUntilEitherKindHasCostATenthOfACent() {
        let nothing = CostNudge.nudges { _ in 0 }
        #expect(nothing == [CostNudge(kind: nil, cost: 0)])
        #expect(nothing.first?.label == "$0 today")
        #expect(nothing.first?.accessibilityLabel == "$0 today")
        #expect(nothing.first?.help.hasPrefix("Today hasn’t cost") == true)
        #expect(CostNudge.nudges { $0 == .llm ? 0.0002 : 0 } == nothing, "a trace of a cent is nothing yet")
        #expect(PromptPreset.exists(CostNudge.symbol), "macOS has the dollar sign")

        let costs: [ProviderKind: Double] = [.llm: 0.0002, .agent: 4]
        let both = CostNudge.nudges { costs[$0]! }
        #expect(both.map(\.kind) == [.llm, .agent], "LLMs first, once either has cost a tenth of a cent")
        #expect(both.map(\.label) == ["$0", UsageInsights.money(4)], "the trace reads as nothing, with no word more")
        #expect(both.map(\.accessibilityLabel) == ["$0 on LLMs today", "\(UsageInsights.money(4)) on agents today"])
        #expect(both[0].help == "What LLMs have cost since midnight, as Settings › Usage counts it.")
        #expect(both[1].help == "What agents have cost since midnight, as Settings › Usage counts it.")
        #expect(CostNudge.nudges { _ in UsageInsights.leastMoney }.allSatisfy { $0.hasCost }, "from the least money writes as a number")
        #expect(UsageInsights.money(UsageInsights.leastMoney).hasPrefix("$"), "so a capsule always shows a number")
        #expect(CostNudge(kind: .llm, cost: 1.5).label == UsageInsights.money(1.5))
    }
}
