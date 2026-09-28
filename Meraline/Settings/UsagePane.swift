import Charts
import SwiftUI

/// Settings › Usage: how Meraline has been used over the last hour, day, week, month, or year, from the usage
/// ledger. A chart of tokens along the span, tiles with the headline numbers, and rows for asking, models and
/// what they cost, and agents, tiles for each game played, then rows for what went with questions, habits, and
/// what was done with answers. Every
/// number is a count; nothing here ever says what was asked or answered.
struct UsagePane: View {
    let ledger: UsageLedger
    @State private var window: UsageWindow
    /// The bar under the pointer, by its label.
    @State private var selectedBar: String?
    @State private var isClearing = false
    /// Moves on while the pane is open, so the spans roll with the clock.
    @State private var now = Date.now

    init(ledger: UsageLedger, window: UsageWindow = .day) {
        self.ledger = ledger
        _window = State(initialValue: window)
    }

    var body: some View {
        Form {
            PaneHeader(pane: .usage, summary: "What you’ve asked, played, and spent, counted on this Mac. Numbers only, never a word of it.")

            Section {
                Picker("Span", selection: $window) {
                    ForEach(UsageWindow.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if insights.isEmpty {
                Section {
                    Text("Nothing in \(window.phrase) yet. Ask something, or play a game, and it shows up here.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                glance
                chart
                asking
                modelsSection
                if insights.tally.agentRuns > 0 { agents }
                if insights.tally.games.values.contains(where: { $0.started > 0 || $0.rounds > 0 }) { games }
                if insights.contextItems > 0 { context }
                habits
            }

            prices
        }
        .formStyle(.grouped)
        .onChange(of: window) { selectedBar = nil }
        .task {
            await ledger.refreshPrices()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
        .confirmationDialog("Clear the usage counts?", isPresented: $isClearing, titleVisibility: .visible) {
            Button("Clear Usage Data", role: .destructive) { ledger.clear() }
        } message: {
            Text("Every count from every span goes, and the file with them. The prices stay.")
        }
    }

    private var insights: UsageInsights {
        UsageInsights(
            tally: ledger.summary(window, now: now),
            window: window,
            activeDays: ledger.activeDays(window, now: now).count,
            longestStreak: ledger.longestStreak(window, now: now),
            busiestHour: ledger.busiestHour(window, now: now),
            busiestWeekday: ledger.busiestWeekday(window, now: now),
            price: ledger.price(forKey:)
        )
    }

    // MARK: At a glance

    private var glance: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
                StatTile(label: "Questions", value: UsageInsights.compact(insights.tally.questions), detail: UsageInsights.count(insights.tally.chats, "chat"))
                StatTile(label: "Answers", value: UsageInsights.compact(insights.tally.answers), detail: UsageInsights.count(insights.tally.wordsRead, "word"))
                StatTile(label: "Tokens in", value: UsageInsights.compact(insights.tally.inputTokens), detail: "prompts and history")
                StatTile(label: "Tokens out", value: UsageInsights.compact(insights.tally.outputTokens), detail: "answers and thinking")
                StatTile(label: "Cost", value: UsageInsights.money(insights.cost), detail: costDetail)
                if insights.tally.rounds > 0 {
                    StatTile(label: "Rounds", value: UsageInsights.compact(insights.tally.rounds), detail: "won \(insights.tally.roundsWon), lost \(insights.tally.roundsLost)")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(window.phrase.capitalizedFirst)
        }
    }

    private var costDetail: String {
        if insights.unpricedAnswers > 0 { return "\(UsageInsights.count(insights.unpricedAnswers, "answer")) unpriced" }
        if insights.estimatedAnswers > 0 { return "\(UsageInsights.count(insights.estimatedAnswers, "answer")) estimated" }
        return "from the providers"
    }

    // MARK: The chart

    private var points: [UsageBar] {
        UsageBar.bars(of: ledger.series(window, now: now), in: window)
    }

    private var chart: some View {
        let points = points
        let peak = max(1, points.map(\.tokens).max() ?? 1)
        return Section {
            Chart(points) { bar in
                BarMark(x: .value("When", bar.label), y: .value("Tokens", bar.tokens), width: .ratio(0.62))
                    .foregroundStyle(bar.isCurrent ? AnyShapeStyle(Color.meralinePink.opacity(0.75)) : AnyShapeStyle(Color.secondary.opacity(0.55)))
                    .cornerRadius(4)
                if let selectedBar, selectedBar == bar.label {
                    RectangleMark(x: .value("When", bar.label))
                        .foregroundStyle(.primary.opacity(0.05))
                        .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            BarTooltip(bar: bar)
                        }
                }
            }
            .chartXSelection(value: $selectedBar)
            .chartYScale(domain: 0...Double(peak) * 1.1)
            .chartXAxis {
                AxisMarks(values: points.filter(\.isTick).map(\.label)) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self), let bar = points.first(where: { $0.label == label }) {
                            Text(bar.tick).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(UsageInsights.compact(tokens)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 150)
            .padding(.vertical, 4)
            .accessibilityLabel("Tokens over \(window.phrase)")
        } header: {
            Text("Tokens over \(window.phrase)")
        } footer: {
            Text("Each bar is \(window.barPhrase); the pink one is now. Move the pointer over a bar for its numbers.")
        }
    }

    // MARK: Rows

    private var asking: some View {
        Section("Asking") {
            row("Questions", UsageInsights.compact(insights.tally.questions), "\(UsageInsights.count(insights.tally.chats, "chat")) started")
            row("Follow-ups", UsageInsights.compact(max(0, insights.tally.questions - insights.tally.chats)), "questions asked in a chat already going")
            row("Words asked", UsageInsights.compact(insights.tally.wordsAsked), "what you typed")
            row("Words read", UsageInsights.compact(insights.tally.wordsRead), insights.averageAnswerWords.map { "about \(UsageInsights.compact($0)) an answer" } ?? "")
            row("Longest chat", UsageInsights.count(insights.tally.longestChat, "turn"), "questions and answers in one chat")
            row("Longest answer", UsageInsights.count(insights.tally.longestAnswer, "word"), "")
            if let favorite = insights.favoriteProvider {
                row("Asked most", favorite.provider.name, UsageInsights.count(favorite.questions, "question"))
            }
            if insights.tally.askAgains > 0 {
                row("Ask Again", UsageInsights.compact(insights.tally.askAgains), "the same question once more")
            }
            if let rewrite = insights.favoriteRewrite {
                row("Rewrites", UsageInsights.compact(insights.rewriteCount), "\(rewrite.rewrite.title) most, \(UsageInsights.count(rewrite.count, "time"))")
            }
            if insights.tally.failures > 0 || insights.tally.stops > 0 {
                row("Didn’t arrive", UsageInsights.compact(insights.tally.failures + insights.tally.stops), "\(UsageInsights.count(insights.tally.failures, "failure")), \(UsageInsights.count(insights.tally.stops, "stop"))")
            }
        }
    }

    private var modelsSection: some View {
        Section {
            ForEach(insights.models, id: \.key) { entry in
                LabeledContent {
                    Text(modelCost(of: entry.key, entry.tally))
                        .monospacedDigit()
                } label: {
                    HStack(spacing: 10) {
                        if let provider = entry.provider {
                            SettingsIcon(symbol: provider.symbol, tint: provider.tint, size: 22)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.model.isEmpty ? "\(entry.provider?.name ?? entry.key)’s own model" : entry.model)
                            Text("\(UsageInsights.count(entry.tally.answers, "answer")) · \(UsageInsights.compact(entry.tally.input + entry.tally.cacheRead + entry.tally.cacheWrite)) in · \(UsageInsights.compact(entry.tally.output)) out\(entry.tally.reportedAnswers < entry.tally.answers ? " · \(entry.tally.answers - entry.tally.reportedAnswers) estimated" : "")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Models")
        } footer: {
            Text("Claude Code, OpenCode, and OpenRouter say what each answer cost. The rest is worked out from their tokens at OpenRouter’s public prices, and an answer whose provider reports no tokens is estimated from its length, about four characters a token.")
        }
    }

    /// What a model's answers cost, or that nothing has priced them.
    private func modelCost(of key: String, _ tally: UsageTally.ModelTally) -> String {
        let price = ledger.price(forKey: key)
        let cost = tally.cost(pricedAt: price)
        if price == nil, cost == 0, tally.unpricedAnswers > 0 { return "no price" }
        return UsageInsights.money(cost)
    }

    private var agents: some View {
        Section("Agents") {
            row("Runs", UsageInsights.compact(insights.tally.agentRuns), "questions to Claude Code, Codex, or OpenCode")
            row("Tools used", UsageInsights.compact(insights.tally.toolUses), insights.tally.mcpUses > 0 ? "\(UsageInsights.compact(insights.tally.mcpUses)) of them MCP tools" : "")
            if insights.tally.asksAllowed + insights.tally.asksDenied > 0 {
                row("Asks", UsageInsights.compact(insights.tally.asksAllowed + insights.tally.asksDenied), "\(insights.tally.asksAllowed) allowed, \(insights.tally.asksDenied) denied")
            }
            if insights.tally.questionsAnswered > 0 {
                row("Questions answered", UsageInsights.compact(insights.tally.questionsAnswered), "the agent’s own questions to you")
            }
            if insights.tally.filesHandedOver > 0 {
                row("Files handed over", UsageInsights.compact(insights.tally.filesHandedOver), "")
            }
        }
    }

    /// Every game together when there was more than one, then a section for each.
    @ViewBuilder private var games: some View {
        let games = insights.games
        if games.count > 1 {
            Section("Games") {
                if let favorite = insights.favoriteGame {
                    row("Played most", favorite.game.title, UsageInsights.count(favorite.rounds, "round"))
                }
                if let best = insights.bestGame {
                    row("Best record", best.game.title, "\(UsageInsights.percent(best.winRate)) of decided rounds won")
                }
                if let rate = insights.winRate {
                    row("Win rate", UsageInsights.percent(rate), "of rounds someone won")
                }
            }
        }
        ForEach(games, id: \.game) { game in
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
                    ForEach(game.figures) { StatTile(label: $0.label, value: $0.value, detail: $0.detail) }
                }
                .padding(.vertical, 4)
            } header: {
                Label(game.game.title, systemImage: game.game.symbol)
            } footer: {
                if let footnote = game.footnote { Text(footnote) }
            }
        }
    }

    private var context: some View {
        Section {
            if insights.tally.selections > 0 { row("Selected text", UsageInsights.compact(insights.tally.selections), "from other apps") }
            if insights.tally.clipboards > 0 { row("Clipboard", UsageInsights.compact(insights.tally.clipboards), "copies added") }
            if insights.tally.screenshots > 0 { row("Screenshots", UsageInsights.compact(insights.tally.screenshots), "") }
            if insights.tally.images > 0 { row("Pictures", UsageInsights.compact(insights.tally.images), "screenshots included") }
            if insights.tally.files > 0 { row("Files", UsageInsights.compact(insights.tally.files), "for agents") }
            if insights.tally.folders > 0 { row("Folders", UsageInsights.compact(insights.tally.folders), "for agents") }
        } header: {
            Text("With your questions")
        }
    }

    private var habits: some View {
        Section {
            if let hour = insights.busiestHour {
                row("Busiest hour", UsageInsights.hour(hour), insights.busiestWeekday.map { "and \(UsageInsights.weekday($0))s most of all" } ?? "")
            }
            if window != .hour && window != .day {
                row("Days with Meraline", UsageInsights.compact(insights.activeDays), insights.longestStreak > 1 ? "\(insights.longestStreak) in a row at most" : "")
            }
            if insights.tally.secondsWaited > 0 {
                row("Waiting for answers", UsageInsights.duration(insights.tally.secondsWaited), insights.averageWait.map { "about \(UsageInsights.duration($0)) each" } ?? "")
            }
            if insights.tally.wordsRead > 0 {
                row("Reading", UsageInsights.duration(insights.readingTime), "at \(Int(UsageInsights.readingSpeed)) words a minute")
            }
            if insights.tally.answersCopied + insights.tally.answersInserted + insights.tally.answersTornOff > 0 {
                row("Answers kept", UsageInsights.compact(insights.tally.answersCopied + insights.tally.answersInserted + insights.tally.answersTornOff),
                    "\(insights.tally.answersCopied) copied, \(insights.tally.answersInserted) inserted, \(insights.tally.answersTornOff) torn off")
            }
        } header: {
            Text("Habits")
        }
    }

    private var prices: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if ledger.isFetchingPrices { ProgressView().controlSize(.small) }
                    Button("Refresh Prices") { Task { await ledger.refreshPrices(force: true) } }
                        .disabled(ledger.isFetchingPrices)
                }
            } label: {
                Text("Prices")
                if let prices = ledger.prices {
                    Text("From OpenRouter’s public list, \(prices.prices.count) models, fetched \(prices.fetched.formatted(date: .abbreviated, time: .shortened)).")
                } else if let failure = ledger.pricesFailure {
                    Text("Not fetched yet: \(failure)")
                } else {
                    Text("Fetched from OpenRouter’s public list when this pane opens.")
                }
            }
            LabeledContent {
                Button("Clear Usage Data…", role: .destructive) { isClearing = true }
                    .disabled(ledger.slots.isEmpty)
            } label: {
                Text("Usage data")
                Text("Kept in ~/Library/Application Support/Meraline/usage.json, as counts by five-minute slot" + (ledger.savedAt.map { ", last written \($0.formatted(date: .omitted, time: .shortened))" } ?? "") + ".")
            }
        }
    }

    private func row(_ label: String, _ value: String, _ detail: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Text(label)
            if !detail.isEmpty { Text(detail) }
        }
    }
}

/// A headline number: its label above, the number large, and a word on it below.
private struct StatTile: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The numbers of the bar under the pointer.
private struct BarTooltip: View {
    let bar: UsageBar

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bar.title).font(.caption.weight(.semibold))
            Text("\(UsageInsights.compact(bar.point.tally.inputTokens)) in · \(UsageInsights.compact(bar.point.tally.outputTokens)) out")
            Text("\(UsageInsights.count(bar.point.tally.questions, "question"))\(bar.point.tally.rounds > 0 ? ", \(UsageInsights.count(bar.point.tally.rounds, "round"))" : "")")
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A bar of the chart: its point, how its axis names it, and how its tooltip does.
nonisolated struct UsageBar: Identifiable, Equatable, Sendable {
    let point: UsagePoint
    /// Unique along the axis; the tick shows only on some bars.
    let label: String
    let tick: String
    let isTick: Bool
    let title: String
    let isCurrent: Bool

    var id: String { label }
    var tokens: Int { point.tally.inputTokens + point.tally.outputTokens }

    /// The bars of a window's series, named along its axis: minutes for an hour, hours for a day, weekdays for
    /// a week, days of the month for a month, months for a year.
    static func bars(of series: [UsagePoint], in window: UsageWindow, calendar: Calendar = .current) -> [UsageBar] {
        let count = series.count
        return series.enumerated().map { index, point in
            let tick: String
            let title: String
            let isTick: Bool
            switch window {
            case .hour:
                tick = point.start.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                title = "\(point.start.formatted(date: .omitted, time: .shortened)) to \(point.end.formatted(date: .omitted, time: .shortened))"
                isTick = index % 3 == 0
            case .day:
                tick = point.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).hour(.defaultDigits(amPM: .abbreviated)).minute(.omitted))
                title = "\(point.start.formatted(.dateTime.weekday(.abbreviated))) \(point.start.formatted(date: .omitted, time: .shortened)) to \(point.end.formatted(date: .omitted, time: .shortened))"
                isTick = index % 6 == 0
            case .week:
                tick = point.start.formatted(.dateTime.weekday(.abbreviated))
                title = point.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                isTick = true
            case .month:
                tick = point.start.formatted(.dateTime.day())
                title = point.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                isTick = index % 5 == 0 || index == count - 1
            case .year:
                tick = point.start.formatted(.dateTime.month(.narrow))
                title = point.start.formatted(.dateTime.month(.wide).year())
                isTick = true
            }
            return UsageBar(point: point, label: "\(index)", tick: tick, isTick: isTick, title: title, isCurrent: index == count - 1)
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

extension UsageWindow {
    /// What one bar of the chart covers.
    var barPhrase: String {
        switch self {
        case .hour: "five minutes"
        case .day: "an hour"
        case .week: "a day"
        case .month: "a day"
        case .year: "a month"
        }
    }
}
