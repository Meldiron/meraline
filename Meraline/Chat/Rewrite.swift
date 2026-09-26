import Foundation

/// The ways the chat's actions can tell the last answer again: shorter, longer, simpler, more concrete, or as
/// a bullet list. The model gets the conversation so far and the instruction, and the answer it writes takes
/// the old one's place (see `ChatSession.rewrite(_:)`), so rewrites build on each other.
nonisolated enum Rewrite: String, CaseIterable, Sendable {
    case shorter
    case longer
    case simpler
    case concrete
    case bulletList

    var title: String {
        switch self {
        case .shorter: "Make Shorter"
        case .longer: "Make Longer"
        case .simpler: "Make Simpler"
        case .concrete: "Make More Concrete"
        case .bulletList: "Turn into Bullet List"
        }
    }

    var symbol: String {
        switch self {
        case .shorter: "arrow.down.right.and.arrow.up.left"
        case .longer: "arrow.up.left.and.arrow.down.right"
        case .simpler: "leaf"
        case .concrete: "scope"
        case .bulletList: "list.bullet"
        }
    }

    /// What the model is asked, after the conversation. It never shows in the panel.
    var instruction: String {
        "\(ask) Reply with only the rewritten answer: no preamble, and no comment on what changed."
    }

    private var ask: String {
        switch self {
        case .shorter:
            "Rewrite your last answer to be much shorter. Keep only what matters most."
        case .longer:
            "Rewrite your last answer in more depth. Add the detail, reasoning, and caveats it left out."
        case .simpler:
            "Rewrite your last answer in plain words for someone new to the topic: no jargon, short sentences."
        case .concrete:
            "Rewrite your last answer to be more concrete. Replace general statements with specific examples, numbers, names, steps, or code."
        case .bulletList:
            "Rewrite your last answer as a Markdown bullet list, one point per bullet, with no paragraphs around it."
        }
    }
}
