import AppKit

/// A prompt that waits above an empty chat as a glass capsule with an icon (see `PromptPresets`): a click puts its
/// text in the input, a Shift-click sends it at once. Each mode has a list of its own, which Settings › Prompt
/// edits, adds to, and deletes from, and a change of mode swaps the rows above the card. Above the card they are
/// for a chat's first question; once an answer is ready, the chat's actions (⌘K) offer them for the answer
/// instead, the first nine on ⌘1…⌘9 (see `ChatSession.run(_:)`). Only a changed list is kept, in UserDefaults,
/// so presets left alone follow later defaults and the language chosen for answers.
nonisolated struct PromptPreset: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    /// An SF Symbol's name.
    var symbol: String
    var text: String

    /// The icon a new preset starts with, and the one shown for a symbol macOS doesn't have.
    static let fallbackSymbol = "text.bubble"

    /// Where a changed list is kept: the LLMs' under the key the one list had before each mode got its own.
    static let key = "promptPresets"

    static func key(for kind: ProviderKind) -> String {
        kind == .llm ? key : "\(key).\(kind.rawValue)"
    }

    /// How many presets the chat's actions give a shortcut, ⌘1 to ⌘9.
    static let shortcutLimit = 9

    /// What the usage ledger counts a preset run on an answer under, among the rewrites: never the preset's name,
    /// which is text of yours.
    static let usageKey = "preset"

    /// The presets a mode starts with, until its list is changed: for the LLMs, work on a text, Translate into the
    /// language chosen for answers; for the agents, work on the files attached and on the web; for decisions,
    /// questions, two of which name their answers after the question mark (see `DecisionAnswers`).
    static func defaults(for kind: ProviderKind, in language: AnswerLanguage) -> [PromptPreset] {
        switch kind {
        case .llm: defaults(in: language)
        case .agent: agentDefaults
        case .decision: decisionDefaults
        }
    }

    static let agentDefaults = [
        PromptPreset(
            id: "findBugs", title: "Find Bugs", symbol: "ant",
            text: "Look through the files attached for bugs, edge cases, and code that could break, and list each one with where it is and how to fix it:"
        ),
        PromptPreset(
            id: "explainCode", title: "Explain Code", symbol: "text.magnifyingglass",
            text: "Explain what the files attached do and how their parts fit together, briefly and in plain words:"
        ),
        PromptPreset(
            id: "writeTests", title: "Write Tests", symbol: "checklist",
            text: "Write tests for the code attached, in its own language and test framework, covering the edge cases, and hand the test file over:"
        ),
        PromptPreset(
            id: "research", title: "Research", symbol: "globe",
            text: "Search the web and answer this in a short summary with its sources, newest first:"
        ),
    ]

    static let decisionDefaults = [
        PromptPreset(id: "urgent", title: "Urgent?", symbol: "exclamationmark.triangle", text: "Is this urgent?"),
        PromptPreset(id: "scam", title: "Scam?", symbol: "shield", text: "Is this a scam, spam, or phishing?"),
        PromptPreset(id: "tone", title: "Tone", symbol: "face.smiling", text: "What is the tone of this text? Friendly / Neutral / Angry"),
        PromptPreset(id: "priority", title: "Priority", symbol: "flag", text: "How high a priority is this? Low < Medium < High"),
    ]

    /// The LLMs' presets until their list is changed. Translate goes into the language chosen for answers.
    static func defaults(in language: AnswerLanguage) -> [PromptPreset] {
        [
            PromptPreset(
                id: "fixGrammar", title: "Fix Grammar", symbol: "text.badge.checkmark",
                text: "Fix the grammar, spelling, and punctuation of this text without changing its wording, tone, or language, and reply with the corrected text only:"
            ),
            PromptPreset(
                id: "antiSlop", title: "Anti-Slop", symbol: "eraser",
                text: "Rewrite this text so it doesn’t read as written by AI: cut filler, hedging, and buzzwords such as delve, seamless, or robust, “not just X but Y”, lists of three, em dashes, and emoji, and keep its meaning, voice, and language. Reply with the rewritten text only:"
            ),
            PromptPreset(
                id: "anonymize", title: "Anonymize", symbol: "theatermasks",
                text: "Anonymize this text: replace the names of people and companies, emails, phone numbers, addresses, and any other detail that could identify someone with placeholders such as [Name] or [Email], change nothing else, and reply with the anonymized text only:"
            ),
            PromptPreset(
                id: "translate", title: "Translate", symbol: "translate",
                text: "Translate this text into \(language.name), keeping its tone and formatting, and reply with the translation only:"
            ),
        ]
    }

    /// A preset for Settings to add, to be named and written there.
    static func blank() -> PromptPreset {
        PromptPreset(id: UUID().uuidString, title: "", symbol: fallbackSymbol, text: "")
    }

    /// The icon to draw: the preset's symbol, or `fallbackSymbol` when macOS has no symbol by that name.
    var shownSymbol: String {
        Self.exists(symbol) ? symbol : Self.fallbackSymbol
    }

    static func exists(_ symbol: String) -> Bool {
        !symbol.isEmpty && NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }

    /// The presets that can run, in their order: those with text.
    static func runnable(_ presets: [PromptPreset]) -> [PromptPreset] {
        presets.filter { !$0.text.trimmed.isEmpty }
    }

    /// What the model is asked when the preset runs on the last answer: the preset's own text, then that the text is
    /// the answer, and to reply with only what comes of it, which takes the answer's place. It never shows. On
    /// haiku and sonnet, the four default presets run on a message to a landlord this way came back as the text
    /// alone every time, and with its details kept.
    var instruction: String {
        "\(text.trimmed)\n\nThe text is your last answer. Reply with only the result: no preamble, and no comment on what changed."
    }

    // MARK: The input

    /// The preset whose text the input starts with, the longest when one's text begins another's.
    static func applied(in draft: String, among presets: [PromptPreset]) -> PromptPreset? {
        let draft = draft.trimmed
        return presets
            .filter { !$0.text.trimmed.isEmpty && draft.hasPrefix($0.text.trimmed) }
            .max { $0.text.trimmed.count < $1.text.trimmed.count }
    }

    /// The input after a click on `preset`: its text first, then whatever was typed, which is never lost. The text
    /// of a preset already there gives way to it, and `toggling` takes out the preset's own text instead, as a
    /// second click on its capsule does. With nothing typed, a space follows the text, ready for what comes next.
    static func draft(_ draft: String, applying preset: PromptPreset, among presets: [PromptPreset], toggling: Bool = true) -> String {
        let applied = applied(in: draft, among: presets)
        let rest = applied.map { String(draft.trimmed.dropFirst($0.text.trimmed.count)).trimmed } ?? draft.trimmed
        if toggling, applied?.id == preset.id { return rest }
        let text = preset.text.trimmed
        return rest.isEmpty ? "\(text) " : "\(text) \(rest)"
    }

    // MARK: Icons

    /// The icons Settings offers for a preset, beside a field for any SF Symbol's name.
    static let symbols = [
        "text.badge.checkmark", "textformat.abc", "eraser", "theatermasks", "translate", "character.bubble", "globe", "text.bubble",
        "quote.bubble", "bubble.left", "text.quote", "list.bullet", "checklist", "list.number", "text.append", "text.redaction",
        "doc.text", "envelope", "pencil", "pencil.line", "highlighter", "scissors", "wand.and.stars", "sparkles",
        "lightbulb", "brain", "questionmark.bubble", "text.magnifyingglass", "chevron.left.forwardslash.chevron.right", "terminal", "ant", "hammer",
        "function", "number", "calendar", "clock", "chart.bar", "face.smiling", "heart", "star",
        "bolt", "flag", "tag", "paperplane", "hand.raised", "shield", "person.fill.questionmark", "textformat.size",
    ]
}

extension ChatSession {
    /// A click on a preset's capsule above the card: its text goes in the input (see
    /// `PromptPreset.draft(_:applying:among:toggling:)`), and with Shift the question goes at once, with whatever
    /// else the draft holds.
    func apply(_ preset: PromptPreset, among presets: [PromptPreset], sending: Bool) {
        guard !isStreaming, !isPlaying else { return }
        draft = PromptPreset.draft(draft, applying: preset, among: presets, toggling: !sending)
        Log.panel.info("Preset \(sending ? "sent" : "put in the input")")
        if sending { send() }
    }

    /// Runs a preset on the last answer, from the chat's actions or its ⌘1…⌘9, as a rewrite: the model reads the
    /// conversation and the preset's text (`PromptPreset.instruction`), and the answer it writes takes the old one's
    /// place under the same question. Stopped or failed partway, the old answer comes back.
    func run(_ preset: PromptPreset) {
        guard !PromptPreset.runnable([preset]).isEmpty else { return }
        rewriteLastAnswer(asking: preset.instruction, countedAs: PromptPreset.usageKey, named: "a preset")
    }

    /// How many of ⌘1…⌘9 run presets on the answer right now, which the mode toggle gives up meanwhile: none until
    /// an answer is ready.
    func presetShortcuts(among presets: [PromptPreset]) -> Int {
        canRewrite ? min(PromptPreset.shortcutLimit, PromptPreset.runnable(presets).count) : 0
    }
}
