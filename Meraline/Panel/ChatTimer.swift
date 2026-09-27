import SwiftUI

/// The capsule under the card's bottom right, lined up with the footer's actions: how long the open chat has
/// before it goes, workspace and all (`ChatSession.chatLifetime`), in minutes and then, in its last one, seconds.
/// Every message starts the time over, and so does a click. Neutral glass, like the buttons above the card, until
/// it reads `warningMinutes` or less: then the active pin's pink, symbol and a faint glass tint.
struct ChatTimer: View {
    let expiresAt: Date
    let keep: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Self.remaining(until: expiresAt, now: context.date)
            let isRunningOut = Self.isRunningOut(until: expiresAt, now: context.date)
            Button(action: keep) {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                    Text(left)
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isRunningOut ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .frame(height: Announcements.size)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(isRunningOut ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
            .animation(.easeInOut(duration: 0.4), value: isRunningOut)
            .help("This chat and its files go when the time runs out. Every message gives it \(Self.lifetime) again, and so does a click.")
            .accessibilityLabel("Time left for this chat")
            .accessibilityValue(left)
            .accessibilityHint("Gives the chat \(Self.lifetime) again")
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    private static var lifetime: String { "\(Int(ChatSession.chatLifetime / 60)) minutes" }

    /// The capsule turns pink once it reads this many minutes left, or less.
    static let warningMinutes = 5

    /// "30 min left" down to "1 min left", then "59 s left" down to "1 s left".
    static func remaining(until deadline: Date, now: Date) -> String {
        let seconds = seconds(until: deadline, now: now)
        return seconds >= 60 ? "\(seconds / 60) min left" : "\(max(1, seconds)) s left"
    }

    /// Whether the capsule reads `warningMinutes` or less, "5 min left" included.
    static func isRunningOut(until deadline: Date, now: Date) -> Bool {
        seconds(until: deadline, now: now) / 60 <= warningMinutes
    }

    private static func seconds(until deadline: Date, now: Date) -> Int {
        Int(max(0, deadline.timeIntervalSince(now)).rounded(.up))
    }
}
