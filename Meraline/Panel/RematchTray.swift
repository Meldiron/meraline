import SwiftUI

/// Play Again, the one game control that stays. Once a round is over it sits under the transcript with how
/// the round went; after the game ends it waits on the empty panel, until a new game or its cross. Beside
/// it, the tally against the model since Meraline opened, which lives in memory only (see `Versus`).
struct RematchTray: View {
    let offer: RematchOffer
    let playAgain: () -> Void
    let putAway: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: offer.game.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.message)
                    .font(.system(size: 13, weight: offer.isAfterGame ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if let tally = offer.versus.tally {
                    Text(tally)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: playAgain) {
                HStack(spacing: 6) {
                    Label("Play Again", systemImage: "arrow.counterclockwise")
                    Text("⌘R").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
            .keyboardShortcut("r")
            .help(offer.isAfterGame ? "Start \(offer.game.title) again (⌘R)" : "Play the next round (Return or ⌘R)")
            if offer.isAfterGame {
                Button(action: putAway) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Put Play Again away until the next game")
                .accessibilityLabel("Put Play Again away")
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(offer.versus.tally.map { "\(offer.game.title), \($0)" } ?? offer.game.title)
    }
}
