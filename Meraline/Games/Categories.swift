import Foundation

/// Categories: the model picks a category, and you and the model take turns naming things in it, you
/// first. The model judges each of yours; one that doesn't fit comes back to you. Six each, unless the
/// model runs out, repeats itself, or you give up.
///
/// The model picks each round's category from three dealt on this Mac, from `categories`: left to itself, it
/// picks Kitchen or Animals every time.
nonisolated enum Categories: GameRules {
    static let title = "Categories"
    static let summary = "Take turns naming things in a category"
    static let symbol = "square.grid.2x2"

    static let perSide = 6
    static let limit = perSide * 2

    static let opening = "Pick a category."
    static let nextCategory = "Pick a new category, different from the ones so far."
    private static let cues: Set<String> = [opening, nextCategory]

    static let systemPrompt = """
    You are playing Categories. When asked to pick a category, reply with just its name and nothing else: one of \
    the categories the message offers, or, when it offers none, a fun, broad category that has plenty of members. \
    Then the user and you take turns naming things that belong to it, the user first. \
    Reply to each thing the user names with one line. If it belongs to the category and nobody has named it yet \
    this round, write “OK: ” followed by one new thing of your own that belongs and hasn't been named. \
    If it doesn't belong, or was already named, write “NO: ” followed by a short, friendly reason. \
    If you can't think of anything new, write “OK: PASS”. No explanations, quotation marks, or Markdown.
    """

    static let invitation = "The model picks a category. Take turns naming things in it, you first; type pass to give up."

    struct Round {
        var category = ""
        var named: [(text: String, byYou: Bool)] = []
        var ending: GameOutcome?
    }

    static func review(_ turns: [ChatSession.Turn]) -> Round {
        var round = Round()
        guard let first = turns.first else { return round }
        round.category = first.reply ?? ""
        for turn in turns.dropFirst() {
            if let outcome = turn.outcome {
                round.ending = outcome
                break
            }
            if !turn.question.isEmpty { round.named.append((turn.question, true)) }
            guard let reply = turn.reply else { continue }
            let word = GameText.verdict(of: reply).rest
            if GameText.isGivingUp(word) {
                round.ending = GameOutcome(text: "The model ran out of ideas. You win!", youWon: true)
                break
            }
            let repeated = round.named.contains { GameText.sameWord($0.text, word) }
            round.named.append((word, false))
            if repeated {
                round.ending = GameOutcome(text: "Foul: “\(word)” was named already. You win!", youWon: true)
                break
            }
        }
        if round.ending == nil, round.named.count >= limit {
            round.ending = GameOutcome(text: "Full house: \(perSide) each and nobody slipped. A draw.", youWon: nil)
        }
        return round
    }

    /// A new round gets three categories to pick from, none the chat has played while there are others.
    static func aside(for turn: ChatSession.Turn, after turns: [ChatSession.Turn], dice: inout GameDice) -> String? {
        guard turn.cue.map(cues.contains) == true else { return nil }
        let played = Set(turns.rounds(cues).map { GameText.key(review($0).category) })
        let offered = dice.deal(offeredCount, from: categories) { !played.contains(GameText.key($0)) }
        return "Pick one of these categories: \(GameText.list(offered))."
    }

    /// How many categories the model picks from.
    static let offeredCount = 3

    /// Categories with plenty of members, for anyone to name six of.
    static let categories = [
        "Things in a kitchen", "Zoo animals", "Things at the beach", "Fruits", "Vegetables", "Sports",
        "Musical instruments", "Things in a bathroom", "Board games", "Things that fly", "Things with wheels",
        "Breakfast foods", "Things in a toolbox", "Jobs", "Things that are cold", "Things that are round",
        "Pizza toppings", "Things in a classroom", "Birds", "Sea creatures", "Insects", "Things in the sky",
        "Winter clothes", "Dog breeds", "Flowers", "Trees", "Desserts", "Things in a garden",
        "Things at a birthday party", "Things in a hospital", "Things in an office", "Things that are red",
        "Things that are yellow", "Things that make noise", "Things in a car", "Things at a campsite",
        "Things in a hotel room", "Things at the airport", "Countries", "Capital cities", "Famous landmarks",
        "Things in space", "Kinds of weather", "Things that are sticky", "Things you plug in", "Kitchen appliances",
        "Furniture", "Things in a supermarket", "Cheeses", "Sandwich fillings", "Drinks", "Herbs and spices",
        "Things made of wood", "Things made of glass", "Things with buttons", "Things that are soft",
        "Things that are sharp", "Things in a bag", "Things at a wedding", "Farm animals", "Pets", "Reptiles",
        "Dinosaurs", "Things in fairy tales", "Superheroes", "Things in a castle", "Things on a pirate ship",
        "Things at a circus", "Olympic sports", "Water sports", "Things in a gym", "Hobbies", "Things people collect",
        "Toys", "Things in a playground", "Things at the cinema", "Movie genres", "Kinds of shoes", "Hats",
        "Things with stripes", "Things with spots", "Things that grow", "Things that melt", "Things that bounce",
        "Things that are hot", "Things in the ocean", "Things in a forest", "Things in a desert", "Things in a city",
        "Kinds of buildings", "Vehicles", "Things in a bakery", "Things in a first aid kit", "Things to pack for a trip",
        "School subjects", "Languages", "Dances", "Kinds of music", "Things with a lid", "Things that come in pairs",
        "Animals with tails", "Nuts and seeds", "Pasta shapes", "Soups", "Candy", "Things in a restaurant",
        "Things in a fridge", "Colors", "Shapes", "Things you do in the morning", "Things with keys",
        "Things in a museum", "Things at a concert", "Things in a library", "Feelings", "Card games", "Video games",
        "Cartoon characters", "Things that are green", "Things in a purse", "Rivers", "Mountains", "Islands",
        "Things you can fold", "Things that tick", "Things with a screen", "Things in a sewing kit", "Breads",
        "Fast food", "Things at a farmers market", "Things you find in a pocket", "Things in a barn"
    ]

    /// The model opens every round, the first with `opening`.
    static func opener(after turns: [ChatSession.Turn], dice: inout GameDice) -> GameOpener {
        .ask(turns.isEmpty ? opening : nextCategory)
    }

    static func state(of turns: [ChatSession.Turn]) -> GameState {
        guard let current = turns.since(cues) else { return GameState(phase: .modelMoves(cue: opening), status: title) }
        let round = review(current)
        let status = round.category.isEmpty ? title : "\(round.category) · \(round.named.count) of \(limit)"
        if current.last?.isComplete == false { return GameState(phase: .waiting, status: status) }
        if let ending = round.ending {
            return GameState(
                phase: .over(outcome: ending, next: GameOpening(placeholder: "Press Return for a new category…", button: "Play Again", takesYourMove: false)),
                status: status
            )
        }
        return GameState(phase: .yourMove(placeholder: "Name one for “\(round.category)”…"), status: status)
    }

    static func play(_ input: String, in turns: [ChatSession.Turn], insisting: Bool) -> GameMove {
        let item = GameText.withoutEndPunctuation(GameText.unwrapped(GameText.firstLine(input)))
        guard !item.isEmpty else { return .reject("Name something first.") }
        if GameText.isGivingUp(item) {
            return .record(item, outcome: GameOutcome(text: "You passed, so the model takes this round.", youWon: false))
        }
        guard GameText.words(item).count <= 4 else { return .reject("Name one thing, in a word or a few.") }
        if let taken = review(turns.since(cues) ?? []).named.first(where: { GameText.sameWord($0.text, item) }) {
            return .reject("“\(taken.text)” is taken already. Name something else.")
        }
        return .ask(item)
    }

    static func judge(_ reply: String, in turns: [ChatSession.Turn]) -> GameReply {
        guard let last = turns.last else { return .refuse("Press Return to ask again.") }
        if last.cue != nil {
            let name = categoryName(reply)
            return name.isEmpty ? .refuse("The model couldn’t think of a category. Press Return to ask again.") : .accept(name)
        }
        let (accepted, rest) = GameText.verdict(of: reply)
        if accepted == false {
            return .refuse(rest.isEmpty ? "The model says “\(last.question)” doesn’t count. Try another." : "Not quite: \(GameText.sentence(rest))")
        }
        var word = rest
        if GameText.words(word).count > 4, let colon = word.lastIndex(of: ":") {
            word = String(word[word.index(after: colon)...])
        }
        word = GameText.withoutEndPunctuation(GameText.unwrapped(word))
        return .accept("OK: \(word.isEmpty || GameText.isGivingUp(word) ? "PASS" : word)")
    }

    static func categoryName(_ reply: String) -> String {
        var name = GameText.unwrapped(GameText.firstLine(reply))
        for prefix in ["category:", "the category is"] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return GameText.withoutEndPunctuation(GameText.unwrapped(name))
    }

    static func lines(for turns: [ChatSession.Turn]) -> [GameLine] {
        var lines = GameLines()
        for current in turns.rounds(cues) {
            let round = review(current)
            guard !round.category.isEmpty else { continue }
            lines.heading(round.category)
            lines.verse(GameLines.chain(round.named.map { ($0.text, $0.byYou ? .you : .model) }, separator: " · "))
            if let ending = round.ending { lines.verdict(ending) }
        }
        return lines.all
    }

    static func transcript(of turns: [ChatSession.Turn]) -> String? {
        let rounds = turns.rounds(cues).map(review).filter { !$0.category.isEmpty }
        guard !rounds.isEmpty else { return nil }
        return rounds.map { round in
            var text = "\(round.category): \(round.named.map(\.text).joined(separator: ", "))"
            if let ending = round.ending { text += "\n\(ending.text)" }
            return text
        }.joined(separator: "\n\n")
    }

    static func headline(of turns: [ChatSession.Turn]) -> String? {
        turns.first?.reply
    }
}
