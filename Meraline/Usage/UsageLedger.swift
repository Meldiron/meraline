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
/// answers, tokens, games, and so on happened when, never a word of them (see `UsageTally`), each slot's apart by
/// the kind of model they came from, the LLMs', the agents', or the decision models'. Settings › Usage reads it
/// by the hour, day, week, month, and year, for the kinds it shows. It lives in Application Support, the one
/// thing Meraline keeps there, and Clear Usage Data in Settings deletes it.
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

    /// Each slot's tallies by kind, by the slot's number: the seconds since 1970 divided by `slotLength`.
    private(set) var slots: [Int: [ProviderKind: UsageTally]] = [:]
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
            let decoder = JSONDecoder()
            let version = try decoder.decode(StoredVersion.self, from: data).version ?? 1
            let stored: StoredLedger
            if version < 2 {
                // Before the counts were kept by kind, a slot was one tally: what it holds says whose it was.
                let old = try decoder.decode(StoredLedgerV1.self, from: data)
                stored = StoredLedger(slots: old.slots.mapValues { tally in
                    Dictionary(uniqueKeysWithValues: tally.byKind().map { ($0.key.rawValue, $0.value) })
                }, savedAt: old.savedAt, prices: old.prices)
            } else {
                stored = try decoder.decode(StoredLedger.self, from: data)
            }
            slots = Dictionary(uniqueKeysWithValues: stored.slots.compactMap { key, kinds in
                Int(key).map { ($0, Dictionary(uniqueKeysWithValues: kinds.compactMap { kind, tally in ProviderKind(rawValue: kind).map { ($0, tally) } })) }
            })
            savedAt = stored.savedAt
            prices = stored.prices
            Log.usage.info("Usage ledger read: \(self.slots.count) slots\(version < 2 ? ", parted by kind" : ""), \(stored.prices?.prices.count ?? 0) prices")
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

    /// Counts something in the slot of `date`, under the kind of model it came from, then writes the ledger soon.
    /// Without a kind, what it counts says whose it is (see `UsageTally.byKind()`).
    func record(at date: Date = .now, as kind: ProviderKind? = nil, _ change: (inout UsageTally) -> Void) {
        var counted = UsageTally()
        change(&counted)
        guard !counted.isEmpty else { return }
        let slot = Self.slot(of: date)
        for (kind, part) in kind.map({ [$0: counted] }) ?? counted.byKind() {
            slots[slot, default: [:]][kind] = (slots[slot]?[kind] ?? UsageTally()) + part
        }
        scheduleSave()
    }

    /// What a slot counted for `kinds`, nil when it counted nothing for them. Its kinds are summed in the
    /// toggle's order.
    private func tally(ofSlot slot: Int, kinds: Set<ProviderKind>) -> UsageTally? {
        guard let counted = slots[slot] else { return nil }
        let parts = ProviderKind.allCases.compactMap { kinds.contains($0) ? counted[$0] : nil }
        return parts.isEmpty ? nil : parts.dropFirst().reduce(parts[0], +)
    }

    /// Everything counted in the window ending at `now`, for `kinds`.
    func summary(_ window: UsageWindow, now: Date = .now, kinds: Set<ProviderKind> = Set(ProviderKind.allCases)) -> UsageTally {
        summary(from: now.addingTimeInterval(-window.length), to: now, kinds: kinds)
    }

    /// Everything counted from `start` up to `end`, for `kinds`, summed slot by slot from the earliest, so games'
    /// runs of wins carry on from one slot into the next.
    func summary(from start: Date, to end: Date, kinds: Set<ProviderKind> = Set(ProviderKind.allCases)) -> UsageTally {
        let first = Self.slot(of: start)
        let last = Self.slot(of: end)
        guard first <= last else { return UsageTally() }
        // A short span, such as today's for the panel's nudge, looks up its own slots rather than going through
        // a year of them.
        let counted = last - first < slots.count
            ? (first...last).filter { slots[$0] != nil }
            : slots.keys.filter { (first...last).contains($0) }.sorted()
        return counted.reduce(UsageTally()) { sum, slot in
            sum + (tally(ofSlot: slot, kinds: kinds) ?? UsageTally())
        }
    }

    /// What one kind of model, the LLMs or the agents, has cost on the calendar day of `date`, for the capsules
    /// under the panel's card (see `CostNudge`).
    func cost(of kind: ProviderKind, onDayOf date: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3_600)
        return summary(from: start, to: end.addingTimeInterval(-1)).cost(of: kind, pricedBy: price(forKey:))
    }

    /// Everything ever counted.
    var allTime: UsageTally {
        let every = Set(ProviderKind.allCases)
        return slots.keys.sorted().reduce(UsageTally()) { $0 + (tally(ofSlot: $1, kinds: every) ?? UsageTally()) }
    }

    /// The window's chart for `kinds`, one point a bar, the last bar ending at `now`. Bars of days and months
    /// follow the calendar, so a week's bars are its days and a year's its months, the last of each cut at `now`.
    func series(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current, kinds: Set<ProviderKind> = Set(ProviderKind.allCases)) -> [UsagePoint] {
        let edges = Self.edges(of: window, now: now, calendar: calendar)
        return zip(edges, edges.dropFirst()).map { start, end in
            UsagePoint(start: start, end: end, tally: summary(from: start, to: end.addingTimeInterval(-1), kinds: kinds))
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

    /// The calendar days with anything counted for `kinds` in the window, most recent last.
    func activeDays(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current, kinds: Set<ProviderKind> = Set(ProviderKind.allCases)) -> [Date] {
        let first = Self.slot(of: now.addingTimeInterval(-window.length))
        let last = Self.slot(of: now)
        let days = Set(slots.keys.filter { (first...last).contains($0) && tally(ofSlot: $0, kinds: kinds)?.isEmpty == false }
            .map { calendar.startOfDay(for: Self.start(ofSlot: $0)) })
        return days.sorted()
    }

    /// The most days in a row with something counted for `kinds`, in the window.
    func longestStreak(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current, kinds: Set<ProviderKind> = Set(ProviderKind.allCases)) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in activeDays(window, now: now, calendar: calendar, kinds: kinds) {
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

    /// The hour of the day (0 to 23) with the most questions for `kinds` in the window, or nil when there were none.
    func busiestHour(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current, kinds: Set<ProviderKind> = Set(ProviderKind.allCases)) -> Int? {
        busiest(window, now: now, kinds: kinds) { calendar.component(.hour, from: $0) }
    }

    /// The weekday (1 is Sunday, as `Calendar` counts) with the most questions for `kinds` in the window.
    func busiestWeekday(_ window: UsageWindow, now: Date = .now, calendar: Calendar = .current, kinds: Set<ProviderKind> = Set(ProviderKind.allCases)) -> Int? {
        busiest(window, now: now, kinds: kinds) { calendar.component(.weekday, from: $0) }
    }

    private func busiest(_ window: UsageWindow, now: Date, kinds: Set<ProviderKind>, by part: (Date) -> Int) -> Int? {
        let first = Self.slot(of: now.addingTimeInterval(-window.length))
        let last = Self.slot(of: now)
        var counts: [Int: Int] = [:]
        for slot in slots.keys where (first...last).contains(slot) {
            guard let tally = tally(ofSlot: slot, kinds: kinds) else { continue }
            let activity = tally.questions + tally.rounds
            guard activity > 0 else { continue }
            counts[part(Self.start(ofSlot: slot)), default: 0] += activity
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    /// The price of `model` at `provider`, as the table has it; a model on this Mac is free, table or none.
    func price(for provider: Provider, model: String) -> ModelPrice? {
        prices?.price(for: provider, model: model) ?? (provider.runsOnThisMac ? .free : nil)
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
        let stored = StoredLedger(slots: Dictionary(uniqueKeysWithValues: slots.map { slot, kinds in
            (String(slot), Dictionary(uniqueKeysWithValues: kinds.map { ($0.key.rawValue, $0.value) }))
        }), savedAt: .now, prices: prices)
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

    /// The file's shape. A slot's number is its key, as text, since JSON keys are, and in it each kind's tally
    /// under the kind's name.
    private struct StoredLedger: Codable {
        var version = 2
        var slots: [String: [String: UsageTally]]
        var savedAt: Date
        var prices: PriceTable?
    }

    /// The file's shape before the counts were kept by kind: one tally a slot.
    private struct StoredLedgerV1: Decodable {
        var slots: [String: UsageTally]
        var savedAt: Date
        var prices: PriceTable?
    }

    private struct StoredVersion: Decodable {
        var version: Int?
    }
}
