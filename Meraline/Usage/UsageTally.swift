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

    /// What this running total grew by since `earlier`: each count that is known, never below zero.
    func subtracting(_ earlier: TokenUsage) -> TokenUsage {
        func grew(_ keyPath: KeyPath<TokenUsage, Int?>) -> Int? {
            self[keyPath: keyPath].map { max(0, $0 - (earlier[keyPath: keyPath] ?? 0)) }
        }
        return TokenUsage(
            input: grew(\.input), output: grew(\.output), cacheRead: grew(\.cacheRead), cacheWrite: grew(\.cacheWrite),
            cost: cost.map { max(0, $0 - (earlier.cost ?? 0)) }, model: model
        )
    }

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
    /// Seconds spent waiting for answers, from a question's sending to its answer's end, and how many waits.
    var secondsWaited = 0.0
    var waits = 0
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

    // What the decision models decided.
    /// Decisions that arrived, answers to questions asked in Decision mode, and those under the Not Sure line.
    var decisions = 0
    var unsureDecisions = 0
    /// Of them, the ones the Context card made as you typed (see `LiveDecisions`).
    var liveDecisions = 0

    /// Games by `Game.rawValue`. Their runs of wins add up in order, so tallies are summed earliest first.
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
        /// Answers costed from their tokens at the prices known when they came.
        var pricedAnswers = 0
        var unpriced = Tokens()

        struct Tokens: Codable, Equatable, Sendable {
            var input = 0
            var output = 0
            var cacheRead = 0
            var cacheWrite = 0

            var isEmpty: Bool { self == Tokens() }

            static func + (a: Tokens, b: Tokens) -> Tokens {
                Tokens(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
            }

            init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
                self.input = input
                self.output = output
                self.cacheRead = cacheRead
                self.cacheWrite = cacheWrite
            }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                input = try values.decodeIfPresent(Int.self, forKey: .input) ?? 0
                output = try values.decodeIfPresent(Int.self, forKey: .output) ?? 0
                cacheRead = try values.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
                cacheWrite = try values.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
            }
        }

        /// Answers priced by nobody yet: neither the provider nor the table known when they came.
        var unpricedAnswers: Int { answers - costedAnswers - pricedAnswers }

        /// What the answers cost, with what `price` says for the tokens no one has priced.
        func cost(pricedAt price: ModelPrice?) -> Double {
            cost + (price.map { $0.cost(of: unpriced) } ?? 0)
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
                pricedAnswers: a.pricedAnswers + b.pricedAnswers,
                unpriced: a.unpriced + b.unpriced
            )
        }

        init(answers: Int = 0, reportedAnswers: Int = 0, input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, cost: Double = 0, costedAnswers: Int = 0, pricedAnswers: Int = 0, unpriced: Tokens = Tokens()) {
            self.answers = answers
            self.reportedAnswers = reportedAnswers
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.cost = cost
            self.costedAnswers = costedAnswers
            self.pricedAnswers = pricedAnswers
            self.unpriced = unpriced
        }

        /// A field a later version adds reads as zero from an older file.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            answers = try values.decodeIfPresent(Int.self, forKey: .answers) ?? 0
            reportedAnswers = try values.decodeIfPresent(Int.self, forKey: .reportedAnswers) ?? 0
            input = try values.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try values.decodeIfPresent(Int.self, forKey: .output) ?? 0
            cacheRead = try values.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
            cacheWrite = try values.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
            cost = try values.decodeIfPresent(Double.self, forKey: .cost) ?? 0
            costedAnswers = try values.decodeIfPresent(Int.self, forKey: .costedAnswers) ?? 0
            pricedAnswers = try values.decodeIfPresent(Int.self, forKey: .pricedAnswers) ?? 0
            unpriced = try values.decodeIfPresent(Tokens.self, forKey: .unpriced) ?? Tokens()
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

    /// One game's rounds, and the numbers of its own that each round adds (`GameFigures`).
    struct GameTally: Codable, Equatable, Sendable {
        var started = 0
        var roundsWon = 0
        var roundsLost = 0
        var roundsDrawn = 0
        /// Moves of yours that went, and ones that came back for breaking a rule.
        var moves = 0
        var rejectedMoves = 0
        var hints = 0
        /// Rounds won in a row: at the start of the tally, at its end, and the most anywhere in it. A draw or a
        /// loss ends a run. They add up in order, earlier tally first, so a span is summed from its earliest slot.
        var winsAtStart = 0
        var winsAtEnd = 0
        var winStreak = 0
        /// The game's own numbers, summed over its rounds, by `GameStat.rawValue`: scores, words, letters, puzzles.
        var counts: [String: Int] = [:]
        /// The most one round has had of them: the best score, the longest word.
        var bests: [String: Int] = [:]

        var rounds: Int { roundsWon + roundsLost + roundsDrawn }

        subscript(stat: GameStat) -> Int { counts[stat.rawValue] ?? 0 }

        func best(_ stat: GameStat) -> Int? { bests[stat.rawValue] }

        /// Counts a round that ended, won when `youWon`, with what the game makes of it.
        mutating func count(round youWon: Bool?, with figures: GameFigures = GameFigures()) {
            var round = GameTally()
            switch youWon {
            case true?:
                round.roundsWon = 1
                round.winsAtStart = 1
                round.winsAtEnd = 1
                round.winStreak = 1
            case false?: round.roundsLost = 1
            case nil: round.roundsDrawn = 1
            }
            round.counts = Dictionary(uniqueKeysWithValues: figures.counts.map { ($0.key.rawValue, $0.value) })
            round.bests = Dictionary(uniqueKeysWithValues: figures.bests.map { ($0.key.rawValue, $0.value) })
            self = self + round
        }

        init(started: Int = 0, roundsWon: Int = 0, roundsLost: Int = 0, roundsDrawn: Int = 0, moves: Int = 0, rejectedMoves: Int = 0, hints: Int = 0,
             winsAtStart: Int = 0, winsAtEnd: Int = 0, winStreak: Int = 0, counts: [String: Int] = [:], bests: [String: Int] = [:]) {
            self.started = started
            self.roundsWon = roundsWon
            self.roundsLost = roundsLost
            self.roundsDrawn = roundsDrawn
            self.moves = moves
            self.rejectedMoves = rejectedMoves
            self.hints = hints
            self.winsAtStart = winsAtStart
            self.winsAtEnd = winsAtEnd
            self.winStreak = winStreak
            self.counts = counts
            self.bests = bests
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            started = try values.decodeIfPresent(Int.self, forKey: .started) ?? 0
            roundsWon = try values.decodeIfPresent(Int.self, forKey: .roundsWon) ?? 0
            roundsLost = try values.decodeIfPresent(Int.self, forKey: .roundsLost) ?? 0
            roundsDrawn = try values.decodeIfPresent(Int.self, forKey: .roundsDrawn) ?? 0
            moves = try values.decodeIfPresent(Int.self, forKey: .moves) ?? 0
            rejectedMoves = try values.decodeIfPresent(Int.self, forKey: .rejectedMoves) ?? 0
            hints = try values.decodeIfPresent(Int.self, forKey: .hints) ?? 0
            winsAtStart = try values.decodeIfPresent(Int.self, forKey: .winsAtStart) ?? 0
            winsAtEnd = try values.decodeIfPresent(Int.self, forKey: .winsAtEnd) ?? 0
            winStreak = try values.decodeIfPresent(Int.self, forKey: .winStreak) ?? 0
            counts = try values.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
            bests = try values.decodeIfPresent([String: Int].self, forKey: .bests) ?? [:]
        }

        /// `b` counted after `a`: a run of wins at the end of `a` carries on into `b`'s.
        static func + (a: GameTally, b: GameTally) -> GameTally {
            GameTally(
                started: a.started + b.started,
                roundsWon: a.roundsWon + b.roundsWon,
                roundsLost: a.roundsLost + b.roundsLost,
                roundsDrawn: a.roundsDrawn + b.roundsDrawn,
                moves: a.moves + b.moves,
                rejectedMoves: a.rejectedMoves + b.rejectedMoves,
                hints: a.hints + b.hints,
                winsAtStart: a.winsAtStart == a.rounds ? a.rounds + b.winsAtStart : a.winsAtStart,
                winsAtEnd: b.winsAtEnd == b.rounds ? b.rounds + a.winsAtEnd : b.winsAtEnd,
                winStreak: max(a.winStreak, b.winStreak, a.winsAtEnd + b.winsAtStart),
                counts: a.counts.merging(b.counts, uniquingKeysWith: +),
                bests: a.bests.merging(b.bests, uniquingKeysWith: max)
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
        sum.waits = a.waits + b.waits
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
        sum.decisions = a.decisions + b.decisions
        sum.unsureDecisions = a.unsureDecisions + b.unsureDecisions
        sum.liveDecisions = a.liveDecisions + b.liveDecisions
        sum.games = a.games.merging(b.games, uniquingKeysWith: +)
        sum.answersCopied = a.answersCopied + b.answersCopied
        sum.answersInserted = a.answersInserted + b.answersInserted
        sum.answersTornOff = a.answersTornOff + b.answersTornOff
        return sum
    }

    /// Counts an answer's tokens and cost under its model, as the provider reported them or as estimated: the
    /// provider's cost when it gave one, else the tokens at `price`, else the tokens wait unpriced.
    mutating func count(answer usage: TokenUsage, reported: Bool, for key: String, price: ModelPrice? = nil) {
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
        } else if let price {
            model.cost += price.cost(of: tokens)
            model.pricedAnswers += 1
        } else {
            model.unpriced = model.unpriced + tokens
        }
        models[key] = model
    }

    /// What every model's answers cost, with `price` for the tokens no one has priced, and how many answers
    /// still have no price at all.
    func cost(pricedBy price: (String) -> ModelPrice?) -> (total: Double, unpricedAnswers: Int) {
        models.reduce((0.0, 0)) { sum, entry in
            let price = price(entry.key)
            return (sum.0 + entry.value.cost(pricedAt: price), sum.1 + (price == nil ? entry.value.unpricedAnswers : 0))
        }
    }

    /// What the models of one kind cost, the LLMs' or the agents', with `price` for the tokens no one has priced.
    func cost(of kind: ProviderKind, pricedBy price: (String) -> ModelPrice?) -> Double {
        models.reduce(0) { sum, entry in
            ModelTally.provider(of: entry.key)?.kind == kind ? sum + entry.value.cost(pricedAt: price(entry.key)) : sum
        }
    }

    /// Whether anything at all was counted.
    var isEmpty: Bool { self == UsageTally() }

    /// A field a later version adds reads as zero from an older file, so the ledger outlives its versions.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) throws -> Int { try values.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        questions = try int(.questions)
        chats = try int(.chats)
        answers = try int(.answers)
        failures = try int(.failures)
        stops = try int(.stops)
        askAgains = try int(.askAgains)
        rewrites = try values.decodeIfPresent([String: Int].self, forKey: .rewrites) ?? [:]
        wordsAsked = try int(.wordsAsked)
        wordsRead = try int(.wordsRead)
        longestChat = try int(.longestChat)
        longestAnswer = try int(.longestAnswer)
        secondsWaited = try values.decodeIfPresent(Double.self, forKey: .secondsWaited) ?? 0
        waits = try int(.waits)
        providers = try values.decodeIfPresent([String: Int].self, forKey: .providers) ?? [:]
        models = try values.decodeIfPresent([String: ModelTally].self, forKey: .models) ?? [:]
        images = try int(.images)
        screenshots = try int(.screenshots)
        files = try int(.files)
        folders = try int(.folders)
        selections = try int(.selections)
        clipboards = try int(.clipboards)
        agentRuns = try int(.agentRuns)
        toolUses = try int(.toolUses)
        mcpUses = try int(.mcpUses)
        asksAllowed = try int(.asksAllowed)
        asksDenied = try int(.asksDenied)
        questionsAnswered = try int(.questionsAnswered)
        filesHandedOver = try int(.filesHandedOver)
        decisions = try int(.decisions)
        unsureDecisions = try int(.unsureDecisions)
        liveDecisions = try int(.liveDecisions)
        games = try values.decodeIfPresent([String: GameTally].self, forKey: .games) ?? [:]
        answersCopied = try int(.answersCopied)
        answersInserted = try int(.answersInserted)
        answersTornOff = try int(.answersTornOff)
    }

    init() {}

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
