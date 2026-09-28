import Foundation

/// What Settings › Usage says about a span: the tally's numbers worked into favorites, rates, and sentences,
/// and the numbers spelled the way the pane shows them. Worked out here, away from the view, so tests can read
/// them.
nonisolated struct UsageInsights: Equatable, Sendable {
    let tally: UsageTally
    let window: UsageWindow
    /// Calendar days with anything counted, and the most in a row.
    let activeDays: Int
    let longestStreak: Int
    /// The hour of the day (0 to 23) and the weekday (1 is Sunday) with the most questions and rounds.
    let busiestHour: Int?
    let busiestWeekday: Int?
    /// What the models cost: what providers reported or the prices known then, plus the prices known now for the
    /// rest, and how many answers still have no price.
    let cost: Double
    let unpricedAnswers: Int

    /// How fast people read, in words a minute, for turning answers into reading time.
    static let readingSpeed = 238.0

    init(tally: UsageTally, window: UsageWindow, activeDays: Int, longestStreak: Int, busiestHour: Int?, busiestWeekday: Int?, price: (String) -> ModelPrice?) {
        self.tally = tally
        self.window = window
        self.activeDays = activeDays
        self.longestStreak = longestStreak
        self.busiestHour = busiestHour
        self.busiestWeekday = busiestWeekday
        let costs = tally.cost(pricedBy: price)
        cost = costs.total
        unpricedAnswers = costs.unpricedAnswers
    }

    /// Whether there is anything to say.
    var isEmpty: Bool { tally.isEmpty }

    /// The provider asked most, with how many questions.
    var favoriteProvider: (provider: Provider, questions: Int)? {
        let counted = tally.providers.compactMap { key, count in Provider(rawValue: key).map { Ranked(item: $0, name: key, score: Double(count)) } }
        return Self.top(of: counted).map { ($0.item, Int($0.score)) }
    }

    /// The game with the most rounds, with how many.
    var favoriteGame: (game: Game, rounds: Int)? {
        let counted = tally.games.compactMap { key, scores in
            Game(rawValue: key).map { Ranked(item: $0, name: key, score: Double(scores.rounds)) }
        }
        return Self.top(of: counted.filter { $0.score > 0 }).map { ($0.item, Int($0.score)) }
    }

    /// The game won most often, of those with three rounds decided, with the share won.
    var bestGame: (game: Game, winRate: Double)? {
        let rated = tally.games.compactMap { key, scores -> Ranked<Game>? in
            guard let game = Game(rawValue: key), scores.roundsWon + scores.roundsLost >= 3 else { return nil }
            return Ranked(item: game, name: key, score: Double(scores.roundsWon) / Double(scores.roundsWon + scores.roundsLost))
        }
        return Self.top(of: rated).map { ($0.item, $0.score) }
    }

    /// Something with a score, and a name to settle ties by.
    private struct Ranked<Item> {
        let item: Item
        let name: String
        let score: Double
    }

    /// The highest scored, the first by name among equals.
    private static func top<Item>(of ranked: [Ranked<Item>]) -> Ranked<Item>? {
        var best: Ranked<Item>?
        for candidate in ranked {
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.score > current.score || (candidate.score == current.score && candidate.name < current.name) {
                best = candidate
            }
        }
        return best
    }

    /// The share of decided rounds you won, over every game.
    var winRate: Double? {
        let decided = tally.roundsWon + tally.roundsLost
        return decided > 0 ? Double(tally.roundsWon) / Double(decided) : nil
    }

    /// The rewrite asked for most.
    var favoriteRewrite: (rewrite: Rewrite, count: Int)? {
        let counted = tally.rewrites.compactMap { key, count in Rewrite(rawValue: key).map { Ranked(item: $0, name: key, score: Double(count)) } }
        return Self.top(of: counted).map { ($0.item, Int($0.score)) }
    }

    var rewriteCount: Int { tally.rewrites.values.reduce(0, +) }

    /// Words in an average answer.
    var averageAnswerWords: Int? {
        tally.answers > 0 ? tally.wordsRead / tally.answers : nil
    }

    /// How long answers took on average, from the question's sending to the answer's end.
    var averageWait: TimeInterval? {
        tally.waits > 0 && tally.secondsWaited > 0 ? tally.secondsWaited / Double(tally.waits) : nil
    }

    /// How long the answers would take to read at `readingSpeed`.
    var readingTime: TimeInterval {
        Double(tally.wordsRead) / Self.readingSpeed * 60
    }

    /// Everything that went with questions besides their words.
    var contextItems: Int {
        tally.images + tally.screenshots + tally.files + tally.folders + tally.selections + tally.clipboards
    }

    /// Answers whose tokens were estimated from their length, since their provider reported none.
    var estimatedAnswers: Int {
        tally.models.values.reduce(0) { $0 + $1.answers - $1.reportedAnswers }
    }

    var totalAnswers: Int {
        tally.models.values.reduce(0) { $0 + $1.answers }
    }

    /// The models by cost, then by tokens, most first, with each one's provider and name.
    var models: [(key: String, provider: Provider?, model: String, tally: UsageTally.ModelTally)] {
        tally.models
            .map { (key: $0.key, provider: UsageTally.ModelTally.provider(of: $0.key), model: UsageTally.ModelTally.model(of: $0.key), tally: $0.value) }
            .sorted { a, b in
                let costA = a.tally.cost, costB = b.tally.cost
                if costA != costB { return costA > costB }
                let tokensA = a.tally.input + a.tally.output, tokensB = b.tally.input + b.tally.output
                return tokensA != tokensB ? tokensA > tokensB : a.key < b.key
            }
    }

    /// The games by rounds, most first, each with the numbers of its own.
    var games: [GameInsights] {
        tally.games.compactMap { key, scores in Game(rawValue: key).map { GameInsights(game: $0, tally: scores) } }
            .sorted { $0.tally.rounds != $1.tally.rounds ? $0.tally.rounds > $1.tally.rounds : $0.game.rawValue < $1.game.rawValue }
    }

    // MARK: Spelling numbers

    /// "1,284", "12.9K", "4.2M", as the Mac's language writes numbers.
    static func compact(_ number: Int, locale: Locale = .current) -> String {
        let magnitude = Double(number)
        func fixed(_ value: Double, _ places: Int) -> String {
            value.formatted(.number.precision(.fractionLength(places)).locale(locale))
        }
        switch abs(number) {
        case ..<10_000: return number.formatted(.number.locale(locale))
        case ..<1_000_000: return fixed(magnitude / 1_000, magnitude < 100_000 ? 1 : 0) + "K"
        case ..<1_000_000_000: return fixed(magnitude / 1_000_000, magnitude < 100_000_000 ? 1 : 0) + "M"
        default: return fixed(magnitude / 1_000_000_000, 1) + "B"
        }
    }

    /// "$4.20", "$0.003", "less than a tenth of a cent" for a trace, "$0" for nothing.
    static func money(_ amount: Double, locale: Locale = .current) -> String {
        if amount == 0 { return "$0" }
        if amount < 0.0005 { return "less than a tenth of a cent" }
        let places = amount < 0.01 ? 3 : amount < 100 ? 2 : 0
        return "$" + amount.formatted(.number.precision(.fractionLength(places)).locale(locale))
    }

    /// "48 s", "12 min", "1 h 12 min", "3 d 4 h".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        let days = hours / 24
        return hours % 24 == 0 ? "\(days) d" : "\(days) d \(hours % 24) h"
    }

    /// "3 PM" or "15:00", as the Mac tells the time.
    static func hour(_ hour: Int, calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = calendar.date(from: components) ?? .now
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar).hour(.defaultDigits(amPM: .abbreviated)).minute(.omitted))
    }

    /// "Tuesday".
    static func weekday(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        return (1...symbols.count).contains(weekday) ? symbols[weekday - 1] : ""
    }

    /// "4.5", "6", an average to one decimal place at most.
    static func average(_ total: Int, over count: Int, locale: Locale = .current) -> String {
        guard count > 0 else { return "0" }
        return (Double(total) / Double(count)).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// "12%" of a share.
    static func percent(_ share: Double, locale: Locale = .current) -> String {
        share.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// "1 question", "12 questions".
    static func count(_ number: Int, _ singular: String, _ plural: String? = nil, locale: Locale = .current) -> String {
        "\(compact(number, locale: locale)) \(number == 1 ? singular : plural ?? singular + "s")"
    }
}
