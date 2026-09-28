import Foundation

/// What a provider says an answer cost: tokens read and written, and money when the provider says so. Fields a
/// provider doesn't report stay nil, so an estimate can fill them in (see `UsageLedger.record(answerOf:)`).
nonisolated struct TokenUsage: Equatable, Sendable {
    var input: Int?
    var output: Int?
    /// Prompt tokens served from a cache, which cost less.
    var cacheRead: Int?
    /// Prompt tokens written to a cache, which cost more.
    var cacheWrite: Int?
    /// What the provider says the answer cost, in US dollars. Claude Code, OpenCode, and OpenRouter say.
    var cost: Double?
    /// The model the provider says answered, when Meraline's settings don't name one, as an agent's don't.
    var model: String?

    static let zero = TokenUsage()

    /// Whether any token count is known.
    var hasTokens: Bool { input != nil || output != nil }

    /// This usage with `other`'s fields taken over it: a later report of the same answer replaces the fields it
    /// carries, or, when `adding`, each of its counts is added to what was known, as OpenCode's steps add up.
    func merging(_ other: TokenUsage, adding: Bool) -> TokenUsage {
        var merged = self
        func take(_ keyPath: WritableKeyPath<TokenUsage, Int?>) {
            guard let value = other[keyPath: keyPath] else { return }
            merged[keyPath: keyPath] = adding ? (merged[keyPath: keyPath] ?? 0) + value : value
        }
        take(\.input)
        take(\.output)
        take(\.cacheRead)
        take(\.cacheWrite)
        if let cost = other.cost { merged.cost = adding ? (merged.cost ?? 0) + cost : cost }
        if let model = other.model { merged.model = model }
        return merged
    }
}

/// How Meraline has been used over some time: counts and sums that add up, and a few most-evers, never a word of
/// what was asked or answered. One tally covers a five-minute slot in the ledger, and any span is the sum of its
/// slots.
nonisolated struct UsageTally: Codable, Equatable, Sendable {
    /// Questions you typed and sent to a model, follow-ups included; not games' moves, Ask Again, or rewrites.
    var questions = 0
    /// Questions that started a chat.
    var chats = 0
    /// Answers that arrived whole.
    var answers = 0
    /// Answers that failed with an error.
    var failures = 0
    /// Answers you stopped.
    var stops = 0
    var askAgains = 0
    /// Rewrites of the last answer, by `Rewrite.rawValue`.
    var rewrites: [String: Int] = [:]
    /// Words in the questions you typed, and in the answers that arrived.
    var wordsAsked = 0
    var wordsRead = 0
    /// The most turns a chat has had, and the most words an answer has.
    var longestChat = 0
    var longestAnswer = 0
    /// Seconds spent waiting for answers, from a question's sending to its answer's end.
    var secondsWaited = 0.0
    /// Questions by `Provider.rawValue`.
    var providers: [String: Int] = [:]
    /// Tokens and cost by model, keyed as `ModelTally.key(provider:model:)`.
    var models: [String: ModelTally] = [:]

    // What went with the questions.
    var images = 0
    var screenshots = 0
    var files = 0
    var folders = 0
    /// Texts selected in other apps, and copies of the clipboard, added to questions.
    var selections = 0
    var clipboards = 0

    // What the agents did.
    var agentRuns = 0
    /// Tools an agent used, and how many of those were MCP tools.
    var toolUses = 0
    var mcpUses = 0
    /// Asks an agent stopped for, by how they were settled.
    var asksAllowed = 0
    var asksDenied = 0
    var questionsAnswered = 0
    /// Files an agent handed over with `present_files`.
    var filesHandedOver = 0

    /// Games by `Game.rawValue`.
    var games: [String: GameTally] = [:]

    // What was done with the answers.
    var answersCopied = 0
    var answersInserted = 0
    var answersTornOff = 0

    /// Tokens and money for one model.
    struct ModelTally: Codable, Equatable, Sendable {
        var answers = 0
        /// Answers whose provider reported its tokens; the rest were estimated from their length.
        var reportedAnswers = 0
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        /// What the answers cost, in US dollars: as the provider reported, or, when it reports no cost, as
        /// estimated from its tokens at the prices known then. Answers with no price known then are counted in
        /// `unpriced`, to be priced when a table arrives.
        var cost = 0.0
        /// Answers whose cost the provider reported.
        var costedAnswers = 0
        var unpriced = Tokens()

        struct Tokens: Codable, Equatable, Sendable {
            var input = 0
            var output = 0
            var cacheRead = 0
            var cacheWrite = 0

            static func + (a: Tokens, b: Tokens) -> Tokens {
                Tokens(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
            }
        }

        static func + (a: ModelTally, b: ModelTally) -> ModelTally {
            ModelTally(
                answers: a.answers + b.answers,
                reportedAnswers: a.reportedAnswers + b.reportedAnswers,
                input: a.input + b.input,
                output: a.output + b.output,
                cacheRead: a.cacheRead + b.cacheRead,
                cacheWrite: a.cacheWrite + b.cacheWrite,
                cost: a.cost + b.cost,
                costedAnswers: a.costedAnswers + b.costedAnswers,
                unpriced: a.unpriced + b.unpriced
            )
        }

        /// How a model is keyed: the provider and the model's name, or the provider alone for an agent that
        /// answers with whatever model it has.
        static func key(provider: Provider, model: String) -> String {
            let model = model.trimmed
            return model.isEmpty ? provider.rawValue : "\(provider.rawValue)/\(model)"
        }

        static func provider(of key: String) -> Provider? {
            Provider(rawValue: String(key.prefix { $0 != "/" }))
        }

        static func model(of key: String) -> String {
            guard let slash = key.firstIndex(of: "/") else { return "" }
            return String(key[key.index(after: slash)...])
        }
    }

    /// One game's rounds.
    struct GameTally: Codable, Equatable, Sendable {
        var started = 0
        var roundsWon = 0
        var roundsLost = 0
        var roundsDrawn = 0
        /// Moves of yours that went, and ones that came back for breaking a rule.
        var moves = 0
        var rejectedMoves = 0
        var hints = 0

        var rounds: Int { roundsWon + roundsLost + roundsDrawn }

        static func + (a: GameTally, b: GameTally) -> GameTally {
            GameTally(
                started: a.started + b.started,
                roundsWon: a.roundsWon + b.roundsWon,
                roundsLost: a.roundsLost + b.roundsLost,
                roundsDrawn: a.roundsDrawn + b.roundsDrawn,
                moves: a.moves + b.moves,
                rejectedMoves: a.rejectedMoves + b.rejectedMoves,
                hints: a.hints + b.hints
            )
        }
    }

    static func + (a: UsageTally, b: UsageTally) -> UsageTally {
        var sum = UsageTally()
        sum.questions = a.questions + b.questions
        sum.chats = a.chats + b.chats
        sum.answers = a.answers + b.answers
        sum.failures = a.failures + b.failures
        sum.stops = a.stops + b.stops
        sum.askAgains = a.askAgains + b.askAgains
        sum.rewrites = a.rewrites.merging(b.rewrites, uniquingKeysWith: +)
        sum.wordsAsked = a.wordsAsked + b.wordsAsked
        sum.wordsRead = a.wordsRead + b.wordsRead
        sum.longestChat = max(a.longestChat, b.longestChat)
        sum.longestAnswer = max(a.longestAnswer, b.longestAnswer)
        sum.secondsWaited = a.secondsWaited + b.secondsWaited
        sum.providers = a.providers.merging(b.providers, uniquingKeysWith: +)
        sum.models = a.models.merging(b.models, uniquingKeysWith: +)
        sum.images = a.images + b.images
        sum.screenshots = a.screenshots + b.screenshots
        sum.files = a.files + b.files
        sum.folders = a.folders + b.folders
        sum.selections = a.selections + b.selections
        sum.clipboards = a.clipboards + b.clipboards
        sum.agentRuns = a.agentRuns + b.agentRuns
        sum.toolUses = a.toolUses + b.toolUses
        sum.mcpUses = a.mcpUses + b.mcpUses
        sum.asksAllowed = a.asksAllowed + b.asksAllowed
        sum.asksDenied = a.asksDenied + b.asksDenied
        sum.questionsAnswered = a.questionsAnswered + b.questionsAnswered
        sum.filesHandedOver = a.filesHandedOver + b.filesHandedOver
        sum.games = a.games.merging(b.games, uniquingKeysWith: +)
        sum.answersCopied = a.answersCopied + b.answersCopied
        sum.answersInserted = a.answersInserted + b.answersInserted
        sum.answersTornOff = a.answersTornOff + b.answersTornOff
        return sum
    }

    /// Counts an answer's tokens and cost under its model, as the provider reported them or as estimated.
    mutating func count(answer usage: TokenUsage, reported: Bool, for key: String) {
        var model = models[key] ?? ModelTally()
        model.answers += 1
        if reported { model.reportedAnswers += 1 }
        let tokens = ModelTally.Tokens(input: usage.input ?? 0, output: usage.output ?? 0, cacheRead: usage.cacheRead ?? 0, cacheWrite: usage.cacheWrite ?? 0)
        model.input += tokens.input
        model.output += tokens.output
        model.cacheRead += tokens.cacheRead
        model.cacheWrite += tokens.cacheWrite
        if let cost = usage.cost {
            model.cost += cost
            model.costedAnswers += 1
        } else {
            model.unpriced = model.unpriced + tokens
        }
        models[key] = model
    }

    /// Whether anything at all was counted.
    var isEmpty: Bool { self == UsageTally() }

    /// Every model's tokens together.
    var inputTokens: Int { models.values.reduce(0) { $0 + $1.input + $1.cacheRead + $1.cacheWrite } }
    var outputTokens: Int { models.values.reduce(0) { $0 + $1.output } }
    var rounds: Int { games.values.reduce(0) { $0 + $1.rounds } }
    var roundsWon: Int { games.values.reduce(0) { $0 + $1.roundsWon } }
    var roundsLost: Int { games.values.reduce(0) { $0 + $1.roundsLost } }

    /// How many words a text has, for counting what was asked and read.
    static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// A rough count of tokens for text a provider reports none for: about four characters a token in English,
    /// which is what the tokenizers of the big models come to.
    static func estimatedTokens(in text: String) -> Int {
        (text.utf8.count + 3) / 4
    }
}
