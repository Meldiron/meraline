import Foundation

/// The instructions Meraline sends a model, each of which Settings › Prompt can change: one for the LLMs, one for
/// the agents, one for each game, and the one Why? asks Claude Code with. Only a changed prompt is kept, in
/// UserDefaults, so a prompt left alone follows its default when a later version changes it.
nonisolated enum SystemPrompt: Hashable, Identifiable, Sendable {
    /// Sent with every question to a mode's providers.
    case chat(ProviderKind)
    /// A game's rules, sent in place of the chat's prompt while the game is on.
    case game(Game)
    /// Why? on an agent's ask (see `ToolReason`).
    case toolReason

    static let allCases: [SystemPrompt] = ProviderKind.allCases.map(chat) + Game.allCases.map(game) + [.toolReason]

    static let llm = """
    You answer quick questions asked from a small floating window. Lead with the answer. \
    Keep it brief: a sentence or a short paragraph, or up to five bullets when a list is clearer. \
    Use Markdown bold, italics, inline code, and links only when they help. \
    Skip headings, preambles, and offers of further help.
    """

    static let agent = """
    You answer questions and carry out tasks asked from a small floating window. \
    Lead with the answer, or with what you did and what came of it. \
    Keep it brief: a sentence or a short paragraph, or up to five bullets when a list is clearer. \
    Use Markdown bold, italics, inline code, and links only when they help. \
    Skip headings, preambles, and offers of further help.
    """

    var id: Self { self }

    /// What the prompt says until it is changed.
    var standard: String {
        switch self {
        case .chat(.llm): Self.llm
        case .chat(.agent): Self.agent
        case .game(let game): game.rules.systemPrompt
        case .toolReason: ToolReason.systemPrompt
        }
    }

    /// Where a changed prompt is kept in UserDefaults.
    var key: String {
        switch self {
        case .chat(let kind): "systemPrompt.\(kind.rawValue)"
        case .game(let game): "systemPrompt.\(game.rawValue)"
        case .toolReason: "systemPrompt.toolReason"
        }
    }

    var title: String {
        switch self {
        case .chat(let kind): kind.pluralTitle
        case .game(let game): game.title
        case .toolReason: "Why?"
        }
    }

    /// The key the one prompt had before each mode got its own. A change kept there carries over to both.
    static let legacyKey = "systemPrompt"
}
