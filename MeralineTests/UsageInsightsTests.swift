import Foundation
import Testing
@testable import Meraline

struct UsageInsightsTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func make(_ tally: UsageTally, price: @escaping (String) -> ModelPrice? = { _ in nil }) -> UsageInsights {
        UsageInsights(tally: tally, window: .week, activeDays: 4, longestStreak: 3, busiestHour: 15, busiestWeekday: 3, price: price)
    }

    @Test func favoritesRatesAndAverages() {
        var tally = UsageTally()
        tally.questions = 10
        tally.answers = 8
        tally.stops = 1
        tally.wordsRead = 800
        tally.secondsWaited = 90
        tally.waits = 9
        tally.providers = ["anthropic": 6, "codex": 4]
        tally.rewrites = ["shorter": 2, "longer": 3]
        tally.games = [
            "rhymeDuel": .init(roundsWon: 2, roundsLost: 2, roundsDrawn: 1),
            "longestWord": .init(roundsWon: 3, roundsLost: 1),
            "categories": .init(roundsWon: 1)
        ]
        tally.count(answer: TokenUsage(input: 100, output: 10), reported: true, for: "anthropic/claude-sonnet-5")
        tally.count(answer: TokenUsage(input: 100, output: 10), reported: false, for: "apple")
        let insights = make(tally) { $0 == "apple" ? .free : ModelPrice(prompt: 0.000003, completion: 0.000015) }

        #expect(insights.favoriteProvider?.provider == .anthropic && insights.favoriteProvider?.questions == 6)
        #expect(insights.favoriteGame?.game == .rhymeDuel && insights.favoriteGame?.rounds == 5)
        #expect(insights.bestGame?.game == .longestWord, "three decided rounds at least")
        #expect(insights.bestGame.map { abs($0.winRate - 0.75) < 0.001 } == true)
        #expect(insights.winRate.map { abs($0 - 6.0 / 9.0) < 0.001 } == true)
        #expect(insights.favoriteRewrite?.rewrite == .longer && insights.rewriteCount == 5)
        #expect(insights.averageAnswerWords == 100)
        #expect(insights.averageWait == 10, "over every wait, moves included")
        #expect(abs(insights.readingTime - 800 / 238 * 60) < 0.01)
        #expect(insights.estimatedAnswers == 1 && insights.totalAnswers == 2)
        #expect(insights.unpricedAnswers == 0)
        #expect(abs(insights.cost - (100 * 0.000003 + 10 * 0.000015)) < 1e-9, "priced now, free on this Mac")
        #expect(insights.models.map(\.key) == ["anthropic/claude-sonnet-5", "apple"], "costliest first")
        #expect(insights.models[1].provider == .apple && insights.models[1].model.isEmpty)
        #expect(insights.games.map(\.game) == [.rhymeDuel, .longestWord, .categories])
        #expect(!insights.isEmpty && make(UsageTally()).isEmpty)
        #expect(make(UsageTally()).favoriteProvider == nil && make(UsageTally()).winRate == nil && make(UsageTally()).averageWait == nil)
    }

    @Test func numbersAreSpelledCompactly() {
        let us = Locale(identifier: "en_US")
        #expect(UsageInsights.compact(0, locale: us) == "0")
        #expect(UsageInsights.compact(999, locale: us) == "999")
        #expect(UsageInsights.compact(1_284, locale: us) == "1,284")
        #expect(UsageInsights.compact(12_900, locale: us) == "12.9K")
        #expect(UsageInsights.compact(120_000, locale: us) == "120K")
        #expect(UsageInsights.compact(4_200_000, locale: us) == "4.2M")
        #expect(UsageInsights.compact(2_500_000_000, locale: us) == "2.5B")
        #expect(UsageInsights.compact(12_900, locale: Locale(identifier: "cs_CZ")) == "12,9K", "as the Mac writes numbers")
        #expect(UsageInsights.money(0) == "$0")
        #expect(UsageInsights.money(0.0001) == "less than a tenth of a cent")
        #expect(UsageInsights.money(0.003, locale: us) == "$0.003")
        #expect(UsageInsights.money(4.2, locale: us) == "$4.20")
        #expect(UsageInsights.money(123.4, locale: us) == "$123")
        #expect(UsageInsights.duration(48) == "48 s")
        #expect(UsageInsights.duration(720) == "12 min")
        #expect(UsageInsights.duration(3_600) == "1 h")
        #expect(UsageInsights.duration(4_320) == "1 h 12 min")
        #expect(UsageInsights.duration(90_000) == "1 d 1 h")
        #expect(UsageInsights.percent(0.75, locale: us) == "75%")
        #expect(UsageInsights.count(1, "question", locale: us) == "1 question")
        #expect(UsageInsights.count(12, "question", locale: us) == "12 questions")
        #expect(UsageInsights.count(3, "reply", "replies", locale: us) == "3 replies")
        #expect(UsageInsights.weekday(3, calendar: utc) == "Tuesday")
        #expect(UsageInsights.weekday(9, calendar: utc).isEmpty)
        #expect(UsageInsights.hour(15, calendar: utc).contains("3") || UsageInsights.hour(15, calendar: utc).contains("15"), "as the Mac tells the time")
    }

    @Test func theChartsBarsAreNamedAlongTheirAxis() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ledger = UsageLedger(file: nil)
        ledger.record(at: now.addingTimeInterval(-60)) { $0.questions += 1; $0.count(answer: TokenUsage(input: 50, output: 5), reported: true, for: "x") }
        let hour = UsageBar.bars(of: ledger.series(.hour, now: now, calendar: utc), in: .hour, calendar: utc)
        #expect(hour.count == 12 && hour.last?.isCurrent == true && hour.last?.tokens == 55)
        #expect(hour.map(\.label) == (0..<12).map(String.init), "unique along the axis")
        #expect(hour.filter(\.isTick).count == 4)
        let week = UsageBar.bars(of: ledger.series(.week, now: now, calendar: utc), in: .week, calendar: utc)
        #expect(week.count == 7 && week.allSatisfy(\.isTick))
        #expect(week.last?.tick.count == 3, "a short weekday")
        let year = UsageBar.bars(of: ledger.series(.year, now: now, calendar: utc), in: .year, calendar: utc)
        #expect(year.count == 12 && year.last?.tick.count == 1, "a month's initial")
        #expect(UsageWindow.year.barPhrase == "a month" && UsageWindow.hour.barPhrase == "five minutes")
    }

    @Test func thePaneHasANameForLinks() {
        #expect(SettingsPane(named: "usage") == .usage)
        #expect(SettingsPane(named: "Stats") == .usage)
        #expect(SettingsPane.usage.title == "Usage")
        #expect(!SettingsPane.usage.symbol.isEmpty)
    }
}
