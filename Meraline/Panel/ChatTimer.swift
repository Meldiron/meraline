import SwiftUI

/// The capsule under the card's bottom right, lined up with the footer's actions: how long the open chat has
/// before it goes, workspace and all (`ChatSession.chatLifetime`), in minutes and then, in its last one, seconds.
/// Every message starts the time over, and so does a click. Neutral glass, like the buttons above the card.
struct ChatTimer: View {
    let expiresAt: Date
    let keep: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Self.remaining(until: expiresAt, now: context.date)
            Button(action: keep) {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                    Text(left)
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: Announcements.size)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("This chat and its files go when the time runs out. Every message gives it \(Self.lifetime) again, and so does a click.")
            .accessibilityLabel("Time left for this chat")
            .accessibilityValue(left)
            .accessibilityHint("Gives the chat \(Self.lifetime) again")
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    private static var lifetime: String { "\(Int(ChatSession.chatLifetime / 60)) minutes" }

    /// "30 min left" down to "1 min left", then "59 s left" down to "1 s left".
    static func remaining(until deadline: Date, now: Date) -> String {
        let seconds = Int(max(0, deadline.timeIntervalSince(now)).rounded(.up))
        return seconds >= 60 ? "\(seconds / 60) min left" : "\(max(1, seconds)) s left"
    }
}
