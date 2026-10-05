import Foundation

/// The SF Symbols this Mac has, and the words each is found by, for the icon picker of Settings › Prompt's
/// presets (`SymbolPicker`). It reads macOS's own catalog of symbols (CoreGlyphs), the one the SF Symbols app
/// searches: every symbol's name in Apple's order, Apple's keywords and categories for it, and the names it had
/// before a rename ("doc.text" is "text.document" now). The variants for other scripts and right-to-left (`.ar`,
/// `.ja`, `.rtl`, …) are left out, since macOS picks those by itself. Should a macOS move that catalog, the picker
/// still has `PromptPreset.symbols` to offer and search by name.
nonisolated struct SymbolCatalog: Sendable {
    struct Symbol: Sendable {
        let name: String
        /// The name's parts: "envelope.badge" is envelope and badge.
        let parts: [String]
        /// Apple's keywords for it, or for its outlined version, split into words, with the parts of its old names.
        let keywords: Set<String>
        let categories: [String]
    }

    /// A category of Apple's, such as Communication or Weather, with its symbols in Apple's order.
    struct Category: Identifiable, Sendable {
        let id: String
        let title: String
        let names: [String]
    }

    let symbols: [Symbol]
    let categories: [Category]
    /// Old names and the names macOS has for them now.
    let aliases: [String: String]

    /// The catalog of the Mac Meraline runs on, read once, at the first look.
    static let shared = system() ?? SymbolCatalog(names: PromptPreset.symbols)

    /// The name macOS has now for a symbol that was renamed, or the name as it is.
    func current(_ name: String) -> String {
        aliases[name] ?? name
    }

    /// A catalog of just these names, without keywords or categories, for a macOS whose catalog can't be read.
    init(names: [String]) {
        symbols = names.map { Symbol(name: $0, parts: $0.components(separatedBy: "."), keywords: [], categories: []) }
        categories = []
        aliases = [:]
    }

    private init(symbols: [Symbol], categories: [Category], aliases: [String: String]) {
        self.symbols = symbols
        self.categories = categories
        self.aliases = aliases
    }

    // MARK: Reading macOS's catalog

    static let systemBundle = URL(filePath: "/System/Library/CoreServices/CoreGlyphs.bundle")

    /// The scripts and directions a symbol has variants for, whose last part names them, as in "character.ja".
    private static let variantSuffixes: Set<String> = [
        "ar", "hi", "he", "ja", "ko", "zh", "th", "bn", "gu", "kn", "ml", "mni", "mr", "or", "pa", "sat", "te", "si",
        "ta", "el", "km", "my", "ru", "rtl",
    ]

    /// Apple's categories worth browsing for an icon, by their keys in the catalog. What's New, Draw, Variable, and
    /// Multicolor sort symbols by how they draw, not what they show, so the picker leaves them out.
    private static let categoryTitles: [String: String] = [
        "communication": "Communication", "weather": "Weather", "maps": "Maps", "objectsandtools": "Objects & Tools",
        "devices": "Devices", "cameraandphotos": "Camera & Photos", "gaming": "Gaming", "connectivity": "Connectivity",
        "transportation": "Transportation", "automotive": "Automotive", "accessibility": "Accessibility",
        "privacyandsecurity": "Privacy & Security", "human": "Human", "home": "Home", "fitness": "Fitness",
        "nature": "Nature", "editing": "Editing", "textformatting": "Text Formatting", "media": "Media",
        "keyboard": "Keyboard", "commerce": "Commerce", "time": "Time", "health": "Health", "shapes": "Shapes",
        "arrows": "Arrows", "indices": "Indices", "math": "Math",
    ]

    static func system(at bundle: URL = systemBundle) -> SymbolCatalog? {
        func read<Value>(_ name: String, as _: Value.Type) -> Value? {
            let url = bundle.appending(path: "Contents/Resources/\(name)")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? Value
        }
        guard let order = read("symbol_order.plist", as: [String].self), !order.isEmpty else { return nil }
        let search = read("symbol_search.plist", as: [String: [String]].self) ?? [:]
        let categoriesOf = read("symbol_categories.plist", as: [String: [String]].self) ?? [:]
        let categoryKeys = (read("categories.plist", as: [[String: String]].self) ?? []).compactMap { $0["key"] }
        let outlined = Dictionary((read("nofill_to_fill.strings", as: [String: String].self) ?? [:]).map { ($1, $0) }) { first, _ in first }
        let renamed = read("name_aliases.strings", as: [String: String].self) ?? [:]

        let known = Set(order)
        let names = order.filter { name in
            guard let dot = name.lastIndex(of: ".") else { return true }
            return !(variantSuffixes.contains(String(name[name.index(after: dot)...])) && known.contains(String(name[..<dot])))
        }
        // Old names that read as words, kept as keywords of the symbol they became; not private ones like "_gm".
        var oldNames: [String: [String]] = [:]
        var aliases: [String: String] = [:]
        for (old, new) in renamed where known.contains(new) && old == old.lowercased() && old.first?.isLetter == true {
            aliases[old] = new
            oldNames[new, default: []].append(old)
        }
        let symbols = names.map { name in
            var keywords = Set((search[name] ?? outlined[name].flatMap { search[$0] } ?? []).flatMap(words))
            for old in oldNames[name] ?? [] { keywords.formUnion(old.components(separatedBy: ".")) }
            return Symbol(name: name, parts: name.components(separatedBy: "."), keywords: keywords, categories: categoriesOf[name] ?? [])
        }
        let categories = categoryKeys.compactMap { key -> Category? in
            guard let title = categoryTitles[key] else { return nil }
            let members = symbols.filter { $0.categories.contains(key) }.map(\.name)
            return members.isEmpty ? nil : Category(id: key, title: title, names: members)
        }
        return SymbolCatalog(symbols: symbols, categories: categories, aliases: aliases)
    }

    /// The words of a keyword or a query, lowercased: "Face ID" is face and id.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

// MARK: Searching

extension SymbolCatalog {
    /// The symbols a search finds, best first. Every word of the query has to find something in a symbol: a part
    /// of its name, one of Apple's keywords for it, the start of either, or its category. Words Apple's keywords
    /// don't know, such as email, urgent, or idea, find what `related` lists for them. A name typed whole comes
    /// first, an old one as its new name. Among symbols as good as each other, the shorter name, then Apple's
    /// order, comes first, so envelope comes before envelope.badge.shield.half.filled.
    func search(_ query: String) -> [String] {
        let exact = current(query.trimmingCharacters(in: .whitespaces).lowercased())
        let terms = Self.words(query).map(searchable).map { word in
            (word: word, related: Self.relatedNames(for: word).map { (name: current($0), parts: $0.split(separator: ".").count) })
        }
        guard !terms.isEmpty else { return [] }
        var found: [(score: Double, index: Int, name: String)] = []
        for (index, symbol) in symbols.enumerated() {
            if symbol.name == exact {
                found.append((.infinity, index, symbol.name))
                continue
            }
            var total = 0.0
            for term in terms {
                let score = max(Self.score(of: term.word, in: symbol), Self.relatedScore(of: term.related, for: symbol))
                guard score > 0 else {
                    total = 0
                    break
                }
                total += score
            }
            guard total > 0 else { continue }
            found.append((total - 1.5 * Double(symbol.parts.count - 1), index, symbol.name))
        }
        return found.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.map(\.name)
    }

    /// A word of the query as it finds the most: as typed, or, when that finds nothing at all, without the ending
    /// of a plural or a tense, so emails finds envelope and translating finds translate.
    private func searchable(_ word: String) -> String {
        guard word.count > 3, !findsAnything(word) else { return word }
        for ending in ["ing", "es", "ed", "s"] where word.hasSuffix(ending) {
            let stem = String(word.dropLast(ending.count))
            if stem.count >= 3, findsAnything(stem) { return stem }
        }
        return word
    }

    private func findsAnything(_ word: String) -> Bool {
        !Self.relatedNames(for: word).isEmpty || symbols.contains { Self.score(of: word, in: $0) > 0 }
    }

    /// How well a word finds a symbol by its name, keywords, and categories, or 0. A short word only finds a whole
    /// part or keyword, or with two letters the start of the name, so "ai" never finds airplane.
    static func score(of word: String, in symbol: Symbol) -> Double {
        let parts = symbol.parts
        if parts.first == word { return 34 }
        if parts.contains(word) { return 30 }
        if symbol.keywords.contains(word) { return 26 }
        guard word.count >= 2 else { return 0 }
        if parts[0].hasPrefix(word) { return word.count >= 3 ? 20 : 12 }
        guard word.count >= 3 else { return 0 }
        if parts.contains(where: { $0.hasPrefix(word) }) { return 17 }
        if symbol.keywords.contains(where: { $0.hasPrefix(word) }) { return 15 }
        if symbol.categories.contains(where: { $0.hasPrefix(word) }) { return 8 }
        if word.count >= 4, parts.contains(where: { $0.contains(word) }) { return 6 }
        return 0
    }

    /// How well a word finds a symbol through `related`, given what it lists for the word: those symbols in their
    /// order, above anything else that matches, then their variants (envelope.fill, envelope.open) with the rest.
    static func relatedScore(of names: [(name: String, parts: Int)], for symbol: Symbol) -> Double {
        var best = 0.0
        for (place, related) in names.enumerated() {
            if symbol.name == related.name {
                // The length penalty `search` takes off is put back: the list is in the order it should show.
                best = max(best, 40 - Double(place) + 1.5 * Double(symbol.parts.count - 1))
            } else if symbol.parts.count - related.parts <= 2, symbol.name.hasPrefix(related.name + ".") {
                best = max(best, 19 - Double(place) / 2)
            }
        }
        return best
    }

    /// What `related` lists for a word, or, while it is being typed, for the words it starts ("ema" for email).
    static func relatedNames(for word: String) -> [String] {
        if let names = related[word] { return names }
        guard word.count >= 3 else { return [] }
        var names: [String] = []
        for key in relatedKeys where key.hasPrefix(word) {
            for name in related[key] ?? [] where !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static let relatedKeys = related.keys.sorted()

    /// Everyday words and the symbols they mean, best first, for the words Apple's keywords miss: what a preset is
    /// for (summary, grammar, urgent, scam), what someone would call a symbol (email, chat, idea, money), and words
    /// a symbol's name hides (bug for ant, AI for sparkles). Each group's words share its symbols. A symbol macOS 27
    /// renamed goes by its old name, which macOS 26 knows and macOS 27 reads as the new one (`current`).
    static let related: [String: [String]] = {
        let groups: [(words: String, symbols: String)] = [
            ("email e-mail mail letter inbox newsletter", "envelope envelope.open tray paperplane"),
            ("chat conversation talk message messages dialog dialogue discuss discussion", "bubble.left.and.bubble.right bubble.left text.bubble ellipsis.bubble quote.bubble"),
            ("reply respond response answer", "arrowshape.turn.up.left bubble.left text.bubble"),
            ("grammar spelling spell proofread proofreading typo typos punctuation correct correction", "text.badge.checkmark textformat.characters character.cursor.ibeam checkmark.circle"),
            ("urgent urgency important alert warning warn caution attention danger dangerous risk", "exclamationmark.triangle exclamationmark.circle exclamationmark.octagon exclamationmark bell.badge"),
            ("money cash price prices cost costs pay payment payments finance financial budget invoice bill salary bank", "dollarsign.circle banknote creditcard eurosign.circle chart.line.uptrend.xyaxis"),
            ("scam fraud phishing spam fake suspicious safe safety secure protect protection", "exclamationmark.shield xmark.shield checkmark.shield shield xmark.bin"),
            ("rocket launch ship release fast quick speed boost", "paperplane bolt hare flame"),
            ("summary summarize summarise summarized tldr digest brief recap overview gist", "text.line.first.and.arrowtriangle.forward list.bullet.rectangle text.page text.quote list.bullet"),
            ("angry anger mad upset furious rude", "flame cloud.bolt exclamationmark.bubble face.smiling"),
            ("happy happiness joy smile smiley friendly fun funny emoji emotion feeling feelings mood sentiment tone", "face.smiling theatermasks heart sun.max"),
            ("sad unhappy sorry", "cloud.rain cloud.drizzle heart.slash"),
            ("priority prioritize rank ranking importance level levels", "flag exclamationmark.2 list.number chart.bar arrow.up.arrow.down"),
            ("idea ideas think thinking thought thoughts brainstorm inspiration creative creativity insight", "lightbulb brain sparkles brain.head.profile"),
            ("rewrite reword rephrase paraphrase edit editing revise improve polish refine fix", "pencil square.and.pencil wand.and.sparkles pencil.and.scribble eraser"),
            ("explain explanation teach learn learning understand simple simplify eli5 lesson tutor", "lightbulb graduationcap book questionmark.bubble character.book.closed"),
            ("test tests testing unittest qa verify verification", "checklist checkmark.circle testtube.2 ant hammer"),
            ("debug debugging bug bugs error errors crash issue issues problem", "ant ladybug exclamationmark.triangle wrench.and.screwdriver"),
            ("web internet online website site browser url", "globe link network safari"),
            ("research investigate investigation explore lookup sources study analyze analyse analysis", "magnifyingglass text.magnifyingglass globe book text.page.badge.magnifyingglass"),
            ("secret private privacy hidden hide anonymous anonymize anonymise incognito redact redaction", "eye.slash theatermasks lock hand.raised text.redaction"),
            ("travel trip vacation holiday flight flights journey", "airplane suitcase map globe.europe.africa"),
            ("world earth global international", "globe globe.europe.africa globe.americas globe.asia.australia"),
            ("translate translation translator language languages foreign", "translate character.bubble globe character.book.closed"),
            ("ok okay yes done approve approved accept accepted agree good correct valid tick", "checkmark checkmark.circle hand.thumbsup checkmark.seal"),
            ("no reject rejected decline wrong bad deny denied cancel invalid", "xmark xmark.circle nosign hand.thumbsdown"),
            ("team group people users community family friends", "person.2 person.3 person.2.wave.2 figure.2"),
            ("user person profile contact account", "person person.circle person.crop.square person.text.rectangle"),
            ("stats statistics analytics data metrics numbers graph report dashboard", "chart.bar chart.pie chart.line.uptrend.xyaxis chart.xyaxis.line tablecells"),
            ("news article articles newspaper blog press headline", "newspaper text.document magazine megaphone"),
            ("file files document documents doc docs page pages paper pdf", "text.document document folder text.page"),
            ("code coding program programming developer dev script scripts software source json html", "chevron.left.forwardslash.chevron.right curlybraces apple.terminal keyboard"),
            ("terminal shell command commands console cli bash", "apple.terminal chevron.left.forwardslash.chevron.right keyboard"),
            ("ai smart magic intelligence assistant bot robot llm gpt automatic auto", "sparkles wand.and.sparkles brain cpu sparkle"),
            ("note notes memo memos jot", "text.pad.header square.and.pencil pencil.and.scribble"),
            ("question questions ask help faq support curious", "questionmark.bubble questionmark.circle questionmark person.fill.questionmark"),
            ("social tweet post posts announce announcement marketing ad ads advert promo promotion campaign", "megaphone bubble.left.and.bubble.right hand.thumbsup heart"),
            ("short shorter shorten concise compress condense trim cut", "arrow.down.right.and.arrow.up.left scissors text.line.first.and.arrowtriangle.forward"),
            ("long longer lengthen expand elaborate extend detail details detailed", "arrow.up.left.and.arrow.down.right text.append text.badge.plus"),
            ("bullet bullets bulleted outline points steps", "list.bullet list.number list.bullet.indent checklist"),
            ("todo todos task tasks checklist chores", "checklist list.bullet.clipboard checkmark.circle"),
            ("table tables spreadsheet csv excel sheet", "tablecells chart.bar list.bullet.rectangle"),
            ("date schedule meeting meetings event events appointment agenda plan planning", "calendar calendar.badge.clock clock person.2"),
            ("deadline time late soon later wait waiting duration", "clock timer hourglass alarm calendar.badge.clock"),
            ("sort order reorder organize organise", "arrow.up.arrow.down list.number folder tray.full"),
            ("compare comparison diff difference versus vs", "arrow.left.arrow.right square.split.2x1 equal"),
            ("legal law lawyer contract contracts terms policy agreement", "building.columns text.document signature scalemass"),
            ("health medical medicine doctor symptom symptoms", "cross stethoscope heart.text.square pills"),
            ("food recipe recipes cook cooking meal meals dinner lunch breakfast", "fork.knife cup.and.saucer carrot birthday.cake"),
            ("shop shopping buy purchase store order orders product products", "cart bag storefront creditcard tag"),
            ("school education study homework exam university student", "graduationcap book books.vertical pencil.and.ruler backpack"),
            ("music song songs lyrics", "music.note microphone guitars"),
            ("image images picture pictures photo photos screenshot", "photo camera photo.on.rectangle"),
            ("video videos movie movies film youtube", "film video play.rectangle"),
            ("phone call calls", "phone iphone"),
            ("location place places address map directions", "mappin.and.ellipse map location signpost.right"),
            ("work job jobs office business career company corporate", "briefcase building.2 case person.text.rectangle"),
            ("gift present birthday", "gift birthday.cake party.popper balloon"),
            ("party celebrate celebration congrats congratulations", "party.popper balloon sparkles birthday.cake"),
            ("love like favorite favourite fav", "heart star hand.thumbsup"),
            ("label labels tag tags category categories classify", "tag folder list.bullet"),
            ("password passwords key keys login credential", "key lock person.badge.key"),
            ("tool tools settings setting config configure configuration setup preferences", "wrench.and.screwdriver gearshape slider.horizontal.3 hammer"),
            ("delete remove clean clear erase", "trash eraser xmark.bin xmark"),
            ("copy duplicate clone", "document.on.document square.on.square"),
            ("paste clipboard", "document.on.clipboard list.clipboard clipboard"),
            ("download save", "square.and.arrow.down arrow.down.circle tray.and.arrow.down"),
            ("upload share export send", "square.and.arrow.up paperplane arrow.up.circle"),
            ("search find look", "magnifyingglass text.magnifyingglass binoculars"),
            ("filter", "line.3.horizontal.decrease line.3.horizontal.decrease.circle"),
            ("again retry redo repeat refresh reload regenerate", "arrow.clockwise arrow.trianglehead.2.clockwise.rotate.90 repeat"),
            ("undo back revert", "arrow.uturn.backward arrow.counterclockwise"),
            ("write writing compose draft author story essay", "pencil square.and.pencil pencil.and.scribble pencil.line text.document"),
            ("read reading reader", "book eyeglasses text.page book.pages"),
            ("quote quotes cite citation citations reference references", "quote.bubble text.quote quote.opening book"),
            ("format formatting style styles font fonts typography markdown", "textformat textformat.size bold italic"),
            ("voice speak speech say audio sound podcast", "waveform microphone speaker.wave.2 captions.bubble"),
            ("listen hear hearing", "ear headphones speaker.wave.2"),
            ("see view watch visible", "eye eyeglasses binoculars"),
            ("lamp bulb light", "lightbulb lightbulb.max sun.max"),
            ("day sun bright morning", "sun.max sunrise"),
            ("night dark moon sleep evening", "moon moon.stars bed.double"),
            ("hot trending trend hype popular", "flame chart.line.uptrend.xyaxis star"),
            ("energy power electric electricity flash", "bolt bolt.circle battery.100percent"),
            ("nature eco green plant plants leaf tree climate environment", "leaf tree globe.europe.africa"),
            ("animal animals pet pets dog cat", "pawprint dog cat bird"),
            ("sport sports fitness gym exercise workout run running", "figure.run dumbbell sportscourt soccerball"),
            ("game games play gaming", "gamecontroller dice puzzlepiece trophy"),
            ("win winner award prize achievement best", "trophy medal crown star"),
            ("discount sale percent percentage", "percent tag"),
            ("math calculate calculation calculator formula equation", "function sum plus.forwardslash.minus divide equal"),
            ("science chemistry physics experiment lab", "atom flask testtube.2"),
            ("weather forecast rain", "cloud.sun cloud.rain umbrella sun.max"),
            ("home house", "house"),
            ("car drive driving", "car"),
            ("notification notifications remind reminder reminders", "bell bell.badge alarm"),
            ("lock locked security", "lock lock.shield key"),
            ("goal goals target focus aim", "target scope flag"),
            ("decision decide decisions choose choice", "arrow.trianglehead.branch questionmark.circle checkmark.circle scalemass"),
            ("hand wave hello hi greeting greet welcome", "hand.wave hand.raised face.smiling"),
            ("thanks thank grateful", "hands.clap heart hand.thumbsup"),
            ("sign signature", "signature pencil.and.scribble"),
            ("highlight highlighter mark", "highlighter pencil.tip"),
            ("draw drawing sketch art design paint", "paintbrush paintpalette pencil.and.scribble scribble"),
            ("color colour colors colours", "paintpalette swatchpalette eyedropper"),
            ("puzzle riddle", "puzzlepiece questionmark"),
            ("star stars rating rate review reviews", "star star.circle hand.thumbsup"),
            ("pin pinned", "pin mappin"),
            ("bookmark bookmarks", "bookmark book"),
            ("computer mac laptop desktop", "desktopcomputer laptopcomputer"),
        ]
        var related: [String: [String]] = [:]
        for group in groups {
            let symbols = group.symbols.split(separator: " ").map(String.init)
            for word in group.words.split(separator: " ").map(String.init) {
                related[word, default: []].append(contentsOf: symbols.filter { !(related[word] ?? []).contains($0) })
            }
        }
        return related
    }()
}
