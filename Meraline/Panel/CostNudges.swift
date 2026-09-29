import SwiftUI

/// What one kind of model, the LLMs or the agents, has cost today, for the capsules under an empty panel.
nonisolated struct CostNudge: Equatable, Identifiable, Sendable {
    let kind: ProviderKind
    let cost: Double

    var id: ProviderKind { kind }

    /// The kinds with a cost to show, LLMs first: each once it has cost a tenth of a cent today, the least
    /// `UsageInsights.money` writes as a number, so a kind not asked today, or free on this Mac, has no capsule.
    /// There is nothing to set: the amounts of Settings › Usage › Daily nudge were removed on purpose.
    static func nudges(cost: (ProviderKind) -> Double) -> [CostNudge] {
        ProviderKind.allCases.compactMap { kind in
            let spent = cost(kind)
            return spent >= UsageInsights.leastMoney ? CostNudge(kind: kind, cost: spent) : nil
        }
    }

    /// "$4.20 on LLMs today", "$12.80 on agents today".
    var label: String { "\(UsageInsights.money(cost)) on \(Self.noun(of: kind)) today" }

    var help: String {
        "What \(Self.noun(of: kind)) have cost since midnight, as Settings › Usage counts it: what the providers reported, or their tokens at OpenRouter’s public prices."
    }

    /// "LLMs" or "agents", in a sentence.
    private static func noun(of kind: ProviderKind) -> String {
        switch kind {
        case .llm: "LLMs"
        case .agent: "agents"
        }
    }
}

/// The capsules under the card's bottom right, where the chat's timer shows while there is a chat: what LLMs and
/// agents have cost today. Only on an empty panel, a quiet reminder before the next chat, never a stop: neutral
/// glass, as the timer is until it runs low, with the pink only in the symbol. They take no click, so the
/// timer's buttons, the only ones that show in their place, never lie on the same spot as others while one row
/// fades into the other, even in the hidden window (see `Announcements`).
struct CostNudges: View {
    let nudges: [CostNudge]

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                ForEach(nudges) { nudge in
                    HStack(spacing: 5) {
                        nudge.kind.image
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.meralinePink)
                        Text(nudge.label)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Announcements.size)
                    .glassEffect(.regular, in: .capsule)
                    .help(nudge.help)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(nudge.label)
                    .transition(.opacity)
                }
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .animation(.smooth(duration: 0.2), value: nudges.map(\.kind))
    }
}
