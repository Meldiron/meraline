import Foundation
@testable import Meraline

/// Five made-up weeks of using Meraline, for the showcase's pictures of Settings › Usage: a few questions most
/// working days, an agent now and then, decisions about mail, and games in the evenings and over lunch. Counted
/// through the ledger as the app counts, each under its kind of model, and the same every time, ending now.
@MainActor
enum DemoUsage {
    private struct Model {
        let provider: Provider
        let name: String
        /// The share of answers, tokens in and out an answer, and dollars a million tokens in and out.
        let share: Double
        let input: Int
        let output: Int
        let prices: (input: Double, output: Double)
    }

    private static let models = [
        Model(provider: .openRouter, name: "anthropic/claude-sonnet-5", share: 0.34, input: 2_400, output: 520, prices: (3, 15)),
        Model(provider: .apple, name: "", share: 0.26, input: 900, output: 260, prices: (0, 0)),
        Model(provider: .anthropic, name: "claude-haiku-4-5", share: 0.2, input: 1_800, output: 380, prices: (1, 5)),
        Model(provider: .openAI, name: "gpt-5-mini", share: 0.12, input: 1_600, output: 450, prices: (0.25, 2)),
        Model(provider: .gemini, name: "gemini-2.5-flash", share: 0.08, input: 1_500, output: 400, prices: (0.3, 2.5))
    ]

    static func fill(_ ledger: UsageLedger, now: Date = .now, calendar: Calendar = .current) {
        var dice = GameDice(seed: 7)
        var decisionDice = GameDice(seed: 11)
        let today = calendar.startOfDay(for: now)
        for back in (0...35).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekend = calendar.isDateInWeekend(day)
            if back > 0, chance(weekend ? 0.55 : 0.1, &dice) { continue }
            let busy = Double.random(in: 0.6...1.4, using: &dice) * (weekend ? 0.5 : 1)
            for hour in 7..<23 {
                for minute in stride(from: 0, to: 60, by: 5) {
                    let moment = day.addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
                    guard moment <= now else { break }
                    guard chance(0.05 * weight(ofHour: hour) * busy, &dice) else { continue }
                    if chance(0.12, &dice) {
                        ledger.record(at: moment, as: .agent) { runAgent(&$0, &dice) }
                    } else {
                        let questions = [1, 1, 1, 2, 3].randomElement(using: &dice) ?? 1
                        ledger.record(at: moment, as: .llm) { tally in
                            for question in 0..<questions { ask(&tally, startingChat: question == 0, &dice) }
                        }
                    }
                    // Mail sorted now and then, by its own draw so the rest stays as it was.
                    if chance(0.2, &decisionDice) {
                        ledger.record(at: moment, as: .decision) { decide(&$0, &decisionDice) }
                    }
                }
            }
            // A few games most evenings, and over lunch now and then.
            let games = back > 0 ? ([0, 1, 2, 3, 4].randomElement(using: &dice) ?? 0) : 2
            for _ in 0..<games {
                let hour = [12, 20, 21, 21, 22].randomElement(using: &dice) ?? 21
                var moment = day.addingTimeInterval(TimeInterval(hour * 3_600 + Int.random(in: 0..<12, using: &dice) * 300))
                if moment > now { moment = now.addingTimeInterval(-TimeInterval(Int.random(in: 1..<48, using: &dice) * 300)) }
                let game = [Game.longestWord, .longestWord, .longestWord, .rhymeDuel, .oddOneOut, .categories].randomElement(using: &dice) ?? .longestWord
                ledger.record(at: moment, as: .llm) { play(game, in: &$0, &dice) }
            }
        }
    }

    /// Busier mid-morning and mid-afternoon, quiet in the evening.
    private static func weight(ofHour hour: Int) -> Double {
        [9: 1.6, 10: 2.2, 11: 1.8, 14: 1.5, 15: 1.9, 16: 1.4, 21: 0.8][hour] ?? ((8...18).contains(hour) ? 0.6 : 0.25)
    }

    private static func chance(_ probability: Double, _ dice: inout GameDice) -> Bool {
        Double.random(in: 0..<1, using: &dice) < probability
    }

    private static func pickModel(_ dice: inout GameDice) -> Model {
        var roll = Double.random(in: 0..<1, using: &dice)
        for model in models {
            roll -= model.share
            if roll < 0 { return model }
        }
        return models[0]
    }

    private static func ask(_ tally: inout UsageTally, startingChat: Bool, _ dice: inout GameDice) {
        let model = pickModel(&dice)
        let input = Int(Double(model.input) * Double.random(in: 0.5...1.6, using: &dice))
        let output = Int(Double(model.output) * Double.random(in: 0.4...1.8, using: &dice))
        tally.questions += 1
        tally.answers += 1
        if startingChat { tally.chats += 1 }
        tally.wordsAsked += Int.random(in: 6...40, using: &dice)
        let words = Int(Double(output) * 0.72)
        tally.wordsRead += words
        tally.longestAnswer = max(tally.longestAnswer, words)
        tally.longestChat = max(tally.longestChat, Int.random(in: 1...6, using: &dice))
        tally.secondsWaited += Double.random(in: 1.2...7.5, using: &dice)
        tally.waits += 1
        tally.providers[model.provider.rawValue, default: 0] += 1
        let key = UsageTally.ModelTally.key(provider: model.provider, model: model.name)
        var entry = tally.models[key] ?? UsageTally.ModelTally()
        entry.answers += 1
        if model.provider != .apple { entry.reportedAnswers += 1 }
        entry.input += input
        entry.output += output
        entry.cost += (Double(input) * model.prices.input + Double(output) * model.prices.output) / 1_000_000
        if model.provider == .openRouter { entry.costedAnswers += 1 } else { entry.pricedAnswers += 1 }
        tally.models[key] = entry
        if chance(0.18, &dice) { tally.selections += 1 }
        if chance(0.1, &dice) { tally.clipboards += 1 }
        if chance(0.06, &dice) {
            tally.screenshots += 1
            tally.images += 1
        }
        if chance(0.3, &dice) { tally.answersCopied += 1 }
        if chance(0.08, &dice) { tally.answersInserted += 1 }
        if chance(0.03, &dice) { tally.answersTornOff += 1 }
        if chance(0.05, &dice) { tally.askAgains += 1 }
        if chance(0.08, &dice), let rewrite = Rewrite.allCases.randomElement(using: &dice) {
            tally.rewrites[rewrite.rawValue, default: 0] += 1
        }
    }

    private static func runAgent(_ tally: inout UsageTally, _ dice: inout GameDice) {
        tally.questions += 1
        tally.answers += 1
        tally.chats += 1
        tally.agentRuns += 1
        let tools = Int.random(in: 2...9, using: &dice)
        tally.toolUses += tools
        tally.mcpUses += Int.random(in: 0...(tools / 2), using: &dice)
        if chance(0.5, &dice) { tally.asksAllowed += 1 }
        if chance(0.08, &dice) { tally.asksDenied += 1 }
        if chance(0.15, &dice) { tally.questionsAnswered += 1 }
        if chance(0.3, &dice) { tally.filesHandedOver += Int.random(in: 1...2, using: &dice) }
        if chance(0.25, &dice) { tally.files += Int.random(in: 1...3, using: &dice) }
        if chance(0.1, &dice) { tally.folders += 1 }
        tally.wordsAsked += Int.random(in: 10...60, using: &dice)
        tally.wordsRead += Int.random(in: 120...420, using: &dice)
        tally.secondsWaited += Double.random(in: 15...90, using: &dice)
        tally.waits += 1
        tally.providers[Provider.claudeCode.rawValue, default: 0] += 1
        let scale = Double.random(in: 0.5...1.8, using: &dice)
        let key = UsageTally.ModelTally.key(provider: .claudeCode, model: "")
        var entry = tally.models[key] ?? UsageTally.ModelTally()
        entry.answers += 1
        entry.reportedAnswers += 1
        entry.input += Int(14_000 * scale)
        entry.output += Int(1_900 * scale)
        entry.cost += 0.07 * scale
        entry.costedAnswers += 1
        tally.models[key] = entry
    }

    /// A question to Jev about a mail or two, some of them about each line, and some answered as you typed.
    private static func decide(_ tally: inout UsageTally, _ dice: inout GameDice) {
        let decided = [1, 1, 1, 2, 6, 12].randomElement(using: &dice) ?? 1
        tally.questions += 1
        tally.answers += 1
        tally.chats += 1
        tally.decisions += decided
        tally.unsureDecisions += chance(0.15, &dice) ? 1 : 0
        if chance(0.3, &dice) { tally.liveDecisions += decided }
        tally.wordsAsked += Int.random(in: 3...9, using: &dice)
        tally.selections += 1
        tally.secondsWaited += Double.random(in: 0.2...0.6, using: &dice)
        tally.waits += 1
        tally.providers[Provider.typeSafe.rawValue, default: 0] += 1
        let input = Int.random(in: 300...2_400, using: &dice) * decided
        let key = UsageTally.ModelTally.key(provider: .typeSafe, model: Provider.typeSafe.defaultModel)
        var entry = tally.models[key] ?? UsageTally.ModelTally()
        entry.answers += 1
        entry.reportedAnswers += 1
        entry.input += input
        entry.output += 4 * decided
        entry.cost += ModelPrice.jev.cost(of: .init(input: input))
        entry.pricedAnswers += 1
        tally.models[key] = entry
    }

    private static func play(_ game: Game, in tally: inout UsageTally, _ dice: inout GameDice) {
        var entry = tally.games[game.rawValue] ?? UsageTally.GameTally()
        entry.started += 1
        entry.moves += [.rhymeDuel: 4, .longestWord: 1, .oddOneOut: 5, .categories: 6][game] ?? 5
        if chance(0.25, &dice) { entry.rejectedMoves += 1 }
        if chance(0.35, &dice) { entry.hints += 1 }
        var figures = GameFigures()
        var youWon: Bool?
        switch game {
        case .rhymeDuel:
            figures.record([5, 6, 7, 7, 8, 8, 9].randomElement(using: &dice) ?? 7, as: .score)
            figures.add(1, to: .rated)
            if chance(0.5, &dice) { figures.add(1, to: .opened) }
        case .longestWord:
            let letters = [5, 6, 6, 7, 7, 8].randomElement(using: &dice) ?? 6
            figures.record(letters, as: .letters)
            figures.add(1, to: .words)
            figures.add(1, to: .modelWords)
            figures.add([5, 6, 6, 7].randomElement(using: &dice) ?? 6, to: .modelLetters)
            figures.add(1, to: .compared)
            if letters >= 7 { figures.add(1, to: .bestFound) }
            youWon = chance(0.6, &dice)
        case .oddOneOut:
            figures.add(3, to: .theirPuzzles)
            figures.add(Int.random(in: 1...3, using: &dice), to: .spotted)
            figures.add(2, to: .yourPuzzles)
            figures.add(Int.random(in: 0...2, using: &dice), to: .fooled)
            youWon = chance(0.62, &dice)
        case .categories:
            figures.add(Int.random(in: 3...6, using: &dice), to: .named)
            if chance(0.4, &dice) { figures.add(1, to: .opened) }
            youWon = chance(0.5, &dice)
        default:
            youWon = chance(0.5, &dice)
        }
        entry.count(round: youWon, with: figures)
        tally.games[game.rawValue] = entry
    }
}
