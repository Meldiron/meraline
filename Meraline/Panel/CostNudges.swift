import SwiftUI

/// A capsule under an empty panel: what the LLMs or the agents have cost today, or, while neither has cost a
/// tenth of a cent, that today has cost nothing yet.
nonisolated struct CostNudge: Equatable, Identifiable, Sendable {
    /// The LLMs or the agents, or nil for the one capsule that stands for both while today has cost nothing.
    let kind: ProviderKind?
    let cost: Double

    var id: String { kind?.rawValue ?? "nothing" }

    /// The capsules for today, from the calendar day's cost of each kind: one for each kind, LLMs first, once
    /// either has cost a tenth of a cent (`UsageInsights.leastMoney`, the least `money` writes as a number), a
    /// kind below that reading "$0"; until then one alone, saying "$0 today". There is nothing to set: the
    /// amounts of Settings › Usage › Daily nudge were removed on purpose.
    static func nudges(cost: (ProviderKind) -> Double) -> [CostNudge] {
        let kinds = ProviderKind.allCases.map { CostNudge(kind: $0, cost: cost($0)) }
        return kinds.contains(where: \.hasCost) ? kinds : [CostNudge(kind: nil, cost: 0)]
    }

    /// Whether the cost is at least a tenth of a cent, which the capsule writes as a number.
    var hasCost: Bool { cost >= UsageInsights.leastMoney }

    /// "$4.20", "$0" for a trace of a cent, and "$0 today" for the capsule that stands for both kinds.
    var label: String {
        let amount = hasCost ? UsageInsights.money(cost) : "$0"
        return kind == nil ? "\(amount) today" : amount
    }

    /// The symbol of the capsule that stands for both kinds; a kind's capsule wears the kind's own picture, as
    /// the mode toggle does.
    static let symbol = "dollarsign.circle"

    var help: String {
        switch kind {
        case .llm?: "What LLMs have cost since midnight, as Settings › Usage counts it."
        case .agent?: "What agents have cost since midnight, as Settings › Usage counts it."
        case nil: "Today hasn’t cost a tenth of a cent yet, as Settings › Usage counts it."
        }
    }

    /// What VoiceOver reads, since the capsule shows only a symbol and an amount.
    var accessibilityLabel: String {
        switch kind {
        case .llm?: "\(label) on LLMs today"
        case .agent?: "\(label) on agents today"
        case nil: label
        }
    }
}

/// The capsules under the card's bottom right, where the chat's timer shows while there is a chat: each kind's
/// symbol from the mode toggle and what it has cost today, or one with a dollar sign saying "$0 today". Only on
/// an empty panel, a quiet reminder before the next chat, never a stop: neutral glass, as the timer is until it
/// runs low, with the pink only in the symbol. Each capsule has a glass container of its own, so its fade
/// reaches its glass, and the row keeps its own size whatever width it is offered, so a label never wraps and
/// the row's right edge stays put. They take no click, so the timer's buttons, the only ones that show in their
/// place, never lie on the same spot as others while one row fades into the other, even in the hidden window
/// (see `Announcements`).
struct CostNudges: View {
    let nudges: [CostNudge]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(nudges) { nudge in
                GlassEffectContainer {
                    HStack(spacing: 5) {
                        (nudge.kind?.image ?? Image(systemName: CostNudge.symbol))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.meralinePink)
                        Text(nudge.label)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Announcements.size)
                    .glassEffect(.regular, in: .capsule)
                }
                .help(nudge.help)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nudge.accessibilityLabel)
                .transition(.opacity)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .animation(.smooth(duration: 0.2), value: nudges.map(\.id))
    }
}
