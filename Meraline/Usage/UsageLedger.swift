import Foundation
import Observation

/// A span Settings › Usage shows: the last hour, day, week, month, or year, ending now.
nonisolated enum UsageWindow: String, CaseIterable, Identifiable, Sendable {
    case hour, day, week, month, year

    var id: Self { self }

    var title: String {
        switch self {
        case .hour: "Hour"
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    /// "the last hour", for sentences.
    var phrase: String {
        switch self {
        case .hour: "the last hour"
        case .day: "the last 24 hours"
        case .week: "the last 7 days"
        case .month: "the last 30 days"
        case .year: "the last 12 months"
        }
    }

    var length: TimeInterval {
        switch self {
        case .hour: 3_600
        case .day: 24 * 3_600
        case .week: 7 * 24 * 3_600
        case .month: 30 * 24 * 3_600
        case .year: 365 * 24 * 3_600
        }
    }

    /// The bars of the window's chart: their number and length, in seconds or in calendar days or months.
    var bars: Bars {
        switch self {
        case .hour: .seconds(5 * 60, count: 12)
        case .day: .seconds(3_600, count: 24)
        case .week: .days(1, count: 7)
        case .month: .days(1, count: 30)
        case .year: .months(1, count: 12)
        }
    }

    enum Bars: Equatable, Sendable {
        case seconds(TimeInterval, count: Int)
        case days(Int, count: Int)
        case months(Int, count: Int)

        var count: Int {
            switch self {
            case .seconds(_, let count), .days(_, let count), .months(_, let count): count
            }
        }
    }
}

/// One bar of a window's chart: what was counted between `start` and `end`.
nonisolated struct UsagePoint: Identifiable, Equatable, Sendable {
    let start: Date
    let end: Date
    let tally: UsageTally

    var id: Date { start }
}

/// The count of how Meraline is used, in five-minute slots, kept on disk as counts alone: how many questions,
/// answers, tokens, games, and so on happened when, never a word of them (see `UsageTally`). Settings › Usage
/// reads it by the hour, day, week, month, and year. It lives in Application Support, the one thing Meraline
/// keeps there, and Clear Usage Data in Settings deletes it.
@Observable
final class UsageLedger {
    /// The slots' length: fine enough for the last hour's chart, coarse enough that a year of heavy use stays a
    /// few megabytes.
    static let slotLength: TimeInterval = 5 * 60

    /// Where the app keeps its ledger. A Debug build run with MERALINE_DEFAULTS_SUITE, as scripts/screenshots.sh
    /// runs it, keeps a throwaway one beside the temporary folder, so the copy you use is never touched.
    static let defaultFile: URL = {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["MERALINE_DEFAULTS_SUITE"] {
            return FileManager.default.temporaryDirectory.appending(path: "\(suite).usage.json")
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Meraline/usage.json")
    }()

    /// The app's ledger. In the test host it stays in memory, as the tests' own ledgers do.
    static let shared = UsageLedger(file: MeralineApp.isHostingTests ? nil : defaultFile)

    /// Each slot's tally, by the slot's number: the seconds since 1970 divided by `slotLength`.
    private(set) var slots: [Int: UsageTally] = [:]
    /// When the ledger was last written, for Settings to say.
    private(set) var savedAt: Date?
    /// OpenRouter's prices, as last fetched (see `PriceTable`), for costing answers whose provider names no cost.
    private(set) var prices: PriceTable?
    private(set) var isFetchingPrices = false
    /// Why the last fetch of prices failed, until one succeeds.
    private(set) var pricesFailure: String?

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// A ledger kept in `file`, read now if it is there, or one in memory alone when `file` is nil.
    init(file: URL?) {
        self.file = file
        guard let file, let data = try? Data(contentsOf: file) else { return }
        do {
            let stored = try JSONDecoder().decode(StoredLedger.self, from: data)
            slots = Dictionary(uniqueKeysWithValues: stored.slots.compactMap { key, tally in Int(key).map { ($0, tally) } })
            savedAt = stored.savedAt
            prices = stored.prices
            Log.usage.info("Usage ledger read: \(self.slots.count) slots, \(stored.prices?.prices.count ?? 0) prices")
        } catch {
            Log.usage.error("Couldn’t read the usage ledger: \(error.localizedDescription)")
        }
    }

    static func slot(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / slotLength).rounded(.down))
    }

    static func start(ofSlot slot: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(slot) * slotLength)
    }

    /// Counts something in the slot of `date`, then writes the ledger soon.
    func record(at date: Date = .now, _ change: (inout UsageTally) -> Void) {
        var tally = slots[Self.slot(of: date)] ?? UsageTally()
        change(&tally)
        slots[Self.slot(of: date)] = tally
        scheduleSave()
    }

    /// Everything counted in the window ending at `now`.
    func summary(_ window: UsageWindow, now: Date = .now) -> UsageTally {
        summary(from: now.addingTimeInterval(-window.length), to: now)
    }

    /// Everything counted from `start` up to `end`, summed slot by slot from the earliest, so games' runs of wins
    /// carry on from one slot into the next.
    func summary(from start: Date, to end: Date) -> UsageTally {
        let first = Self.slot(of: start)
        let last = Self.slot(of: end)
        return slots.keys.filter { (first...last).contains($0) }.sorted().reduce(UsageTally()) { sum, slot in
            sum + (slots[slot] ?? UsageTally())
        }
    }

    /// Everything ever counted.
    var allTime: UsageTally {
        slots.keys.sorted().reduce(UsageTally()) { $0 + (slots[$1] ?? UsageTally()) }
    }

    /// The window's chart, one point a bar, the last bar ending at `now`. Bars of days and months follow the
    /// calendar, so a week's bars are its days and a year's its months, the last of each cut at `now`.
    func series(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current) -> [UsagePoint] {
        let edges = Self.edges(of: window, now: now, calendar: calendar)
        return zip(edges, edges.dropFirst()).map { start, end in
            UsagePoint(start: start, end: end, tally: summary(from: start, to: end.addingTimeInterval(-1)))
        }
    }

    /// The bars' starts and, last, the window's end.
    static func edges(of window: UsageWindow, now: Date, calendar: Calendar) -> [Date] {
        switch window.bars {
        case .seconds(let length, let count):
            return (0...count).map { now.addingTimeInterval(TimeInterval($0 - count) * length) }
        case .days(let days, let count):
            let today = calendar.startOfDay(for: now)
            let starts = (0..<count).compactMap { calendar.date(byAdding: .day, value: ($0 - count + 1) * days, to: today) }
            return starts + [now]
        case .months(let months, let count):
            let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let starts = (0..<count).compactMap { calendar.date(byAdding: .month, value: ($0 - count + 1) * months, to: thisMonth) }
            return starts + [now]
        }
    }

    /// The calendar days with anything counted in the window, most recent last.
    func activeDays(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let first = Self.slot(of: now.addingTimeInterval(-window.length))
        let last = Self.slot(of: now)
        let days = Set(slots.keys.filter { (first...last).contains($0) && slots[$0]?.isEmpty == false }
            .map { calendar.startOfDay(for: Self.start(ofSlot: $0)) })
        return days.sorted()
    }

    /// The most days in a row with something counted, in the window.
    func longestStreak(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in activeDays(window, now: now, calendar: calendar) {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    /// The hour of the day (0 to 23) with the most questions in the window, or nil when there were none.
    func busiestHour(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current) -> Int? {
        busiest(window, now: now) { calendar.component(.hour, from: $0) }
    }

    /// The weekday (1 is Sunday, as `Calendar` counts) with the most questions in the window.
    func busiestWeekday(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current) -> Int? {
        busiest(window, now: now) { calendar.component(.weekday, from: $0) }
    }

    private func busiest(_ window: UsageWindow, now: Date, by part: (Date) -> Int) -> Int? {
        let first = Self.slot(of: now.addingTimeInterval(-window.length))
        let last = Self.slot(of: now)
        var counts: [Int: Int] = [:]
        for (slot, tally) in slots where (first...last).contains(slot) {
            let activity = tally.questions + tally.rounds
            guard activity > 0 else { continue }
            counts[part(Self.start(ofSlot: slot)), default: 0] += activity
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    /// The price of `model` at `provider`, as the table has it; a model on this Mac is free, table or none.
    func price(for provider: Provider, model: String) -> ModelPrice? {
        prices?.price(for: provider, model: model) ?? ((provider.isOnDevice || provider == .ollama) ? .free : nil)
    }

    /// The price of the model a tally is keyed by.
    func price(forKey key: String) -> ModelPrice? {
        guard let provider = UsageTally.ModelTally.provider(of: key) else { return nil }
        return price(for: provider, model: UsageTally.ModelTally.model(of: key))
    }

    /// Fetches OpenRouter's prices when the table is missing or a day old, or when `force`d, and keeps them.
    func refreshPrices(force: Bool = false, fetch: () async throws -> PriceTable = { try await PriceTable.fetch() }) async {
        guard force || prices == nil || prices?.isStale == true, !isFetchingPrices else { return }
        isFetchingPrices = true
        defer { isFetchingPrices = false }
        do {
            let table = try await fetch()
            prices = table
            pricesFailure = nil
            Log.usage.info("Prices fetched for \(table.prices.count) models")
            scheduleSave()
        } catch {
            pricesFailure = error.localizedDescription
            Log.usage.error("Couldn’t fetch prices: \(error.localizedDescription)")
        }
    }

    /// Forgets everything and deletes the file. The prices stay, as they are nobody's usage.
    func clear() {
        slots = [:]
        savedAt = nil
        pendingSave?.cancel()
        pendingSave = nil
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
        Log.usage.info("Usage ledger cleared")
    }

    /// Writes the ledger a moment after the last change, so a burst of counts is one write.
    private func scheduleSave() {
        guard file != nil else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Writes the ledger now.
    func save() async {
        guard let file else { return }
        let stored = StoredLedger(slots: Dictionary(uniqueKeysWithValues: slots.map { (String($0.key), $0.value) }), savedAt: .now, prices: prices)
        do {
            let data = try JSONEncoder().encode(stored)
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            }.value
            savedAt = stored.savedAt
        } catch {
            Log.usage.error("Couldn’t write the usage ledger: \(error.localizedDescription)")
        }
    }

    /// The file's shape. A slot's number is its key, as text, since JSON keys are.
    private struct StoredLedger: Codable {
        var version = 1
        var slots: [String: UsageTally]
        var savedAt: Date
        var prices: PriceTable?
    }
}
