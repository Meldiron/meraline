import Foundation

/// How a game has gone against the model since Meraline opened: the rounds you won, the ones the model
/// won, and the ones nobody did. `ChatSession` counts each round as it ends and keeps the count in memory
/// only, like Recent Chats, so quitting forgets it.
nonisolated struct Versus: Equatable, Sendable {
    private(set) var you = 0
    private(set) var model = 0
    private(set) var even = 0

    var rounds: Int { you + model + even }

    mutating func record(_ outcome: GameOutcome) {
        switch outcome.youWon {
        case true?: you += 1
        case false?: model += 1
        case nil: even += 1
        }
    }

    /// "You 2 – 1 Model", with the draws after it, or how many rounds were played when nobody wins them.
    var tally: String? {
        guard rounds > 0 else { return nil }
        guard you + model > 0 else { return rounds == 1 ? "1 round played" : "\(rounds) rounds played" }
        let score = "You \(you) – \(model) Model"
        guard even > 0 else { return score }
        return "\(score) · \(even) \(even == 1 ? "draw" : "draws")"
    }
}

/// What the rematch tray shows: a game to play again, how it has gone, and a line to go with it.
nonisolated struct RematchOffer: Equatable, Sendable {
    let game: Game
    /// The round's outcome while the game is open, or the game's title once it has ended.
    let message: String
    let versus: Versus
    /// Whether the game has ended and the tray sits on an empty panel, where it can be put away.
    let isAfterGame: Bool
}
