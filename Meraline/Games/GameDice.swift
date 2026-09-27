import Foundation

/// The dice the games roll on this Mac. Asked the same thing, a model picks the same way every time, however it
/// is told to pick at random: the same opening line, the same category, the same word. So whatever should change
/// from one game to the next, a story's subject, the words a line may end on, the categories to choose from, is
/// drawn here and goes to the model with the move as the turn's `aside` (see `GameRules.aside(for:after:dice:)`).
///
/// A seed makes the draws repeat, for tests; without one they come from the system's generator.
nonisolated struct GameDice: RandomNumberGenerator, Sendable {
    private var state: UInt64?

    init() {}

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        guard var z = state else {
            var system = SystemRandomNumberGenerator()
            return system.next()
        }
        // SplitMix64: small, fast, and good enough to shuffle a list of words.
        z &+= 0x9E37_79B9_7F4A_7C15
        state = z
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `count` different items of `items` in random order, taken first from those `isFresh` lets through, so a
    /// chat doesn't see the same one twice until it has seen them all.
    mutating func deal<Item>(_ count: Int, from items: [Item], preferring isFresh: (Item) -> Bool = { _ in true }) -> [Item] {
        let fresh = items.filter(isFresh).shuffled(using: &self)
        guard fresh.count < count else { return Array(fresh.prefix(count)) }
        let stale = items.filter { !isFresh($0) }.shuffled(using: &self)
        return Array((fresh + stale).prefix(count))
    }

    /// One of `items`, a fresh one when there is one.
    mutating func pick<Item>(from items: [Item], preferring isFresh: (Item) -> Bool = { _ in true }) -> Item? {
        deal(1, from: items, preferring: isFresh).first
    }
}
