import SwiftUI

/// What one kind of model, the LLMs or the agents, has cost today, once that is past the amount set for it in
/// Settings › Usage (`Preferences.costNudges`).
nonisolated struct CostNudge: Equatable, Identifiable, Sendable {
    let kind: ProviderKind
    let cost: Double
    let limit: Double

    var id: ProviderKind { kind }

    /// The amount a kind starts at when its nudge is switched on: an LLM's answers cost cents, an agent's run can
    /// cost a dollar.
    static func standardLimit(for kind: ProviderKind) -> Double {
        switch kind {
        case .llm: 1
        case .agent: 10
        }
    }

    /// The kinds past their amount, LLMs first. None has an amount until you set one.
    static func nudges(limits: [ProviderKind: Double], cost: (ProviderKind) -> Double) -> [CostNudge] {
        ProviderKind.allCases.compactMap { kind in
            guard let limit = limits[kind] else { return nil }
            let spent = cost(kind)
            return spent > limit ? CostNudge(kind: kind, cost: spent, limit: limit) : nil
        }
    }

    /// "$4.20 on LLMs today", "$12 on agents today".
    var label: String { "\(UsageInsights.money(cost)) on \(Self.noun(of: kind)) today" }

    var help: String {
        "\(kind.pluralTitle) have cost \(UsageInsights.money(cost)) today, past the \(UsageInsights.money(limit)) set in Settings › Usage."
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
/// agents have cost today, each once past its amount. Only on an empty panel, a soft nudge before the next chat,
/// never a stop: neutral glass, as the timer is until it runs low, with the pink only in the symbol. They take no
/// click, so the timer, the one button that shows in their place, never lies on the same spot as another while
/// one fades into the other, even in the hidden window (see `Announcements`).
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
