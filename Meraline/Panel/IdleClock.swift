import Foundation
import SwiftUI

/// The clock behind Start a New Chat in Settings › General (`IdleReset`). It runs while you are away from the
/// window, from the moment it hides or, pinned, loses the keyboard, and stops when you come back to it. When it
/// runs out, the chat moves to Recent Chats, or is forgotten if it is anonymous, and the next question starts
/// fresh. That happens on time, whether the window is hidden or still on the screen, where the pin counts down to
/// it (`PinButton`). An answer still coming keeps the chat, and the clock starts over once it has arrived.
final class IdleClock {
    private let session: ChatSession
    private let preferences: Preferences
    private let layout: PanelLayout
    /// When you left the window, or nil while you use it.
    private(set) var leftAt: Date?
    private var timer: Task<Void, Never>?

    init(session: ChatSession, preferences: Preferences, layout: PanelLayout) {
        self.session = session
        self.preferences = preferences
        self.layout = layout
        observeSetting()
    }

    /// You left the window. Leaving it again, as when a pinned window you left is then hidden, keeps the time
    /// you first left.
    func leave(at date: Date = .now) {
        guard leftAt == nil else { return }
        leftAt = date
        schedule()
    }

    /// You came back to the window. A chat away for long enough goes first, in case the clock is late, as it
    /// can be after the Mac sleeps.
    func comeBack(at date: Date = .now) {
        if preferences.idleReset.hasExpired(since: leftAt, now: date) { session.expire() }
        leftAt = nil
        schedule()
    }

    /// Sets the clock to run out when the setting says, or stops it: while you use the window, under Never, and
    /// with no chat to move on.
    private func schedule() {
        timer?.cancel()
        timer = nil
        guard let leftAt, let interval = preferences.idleReset.interval, !session.turns.isEmpty || session.isPlaying else {
            layout.forgetsAt = nil
            return
        }
        let deadline = leftAt.addingTimeInterval(interval)
        layout.forgetsAt = deadline
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.runOut()
        }
    }

    private func runOut() {
        if session.isStreaming {
            leftAt = .now
            Log.panel.info("Idle clock ran out during an answer; starting it over")
            restartWhenAnswered()
        } else {
            session.expire()
            Log.panel.info("Idle clock ran out after \(self.preferences.idleReset.rawValue) minutes; the next question starts fresh")
        }
        schedule()
    }

    /// Starts the clock over when the answer that kept the chat has arrived, so a long one still gets the whole
    /// wait, unless you came back to the window meanwhile.
    private func restartWhenAnswered() {
        withObservationTracking {
            _ = session.isStreaming
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.leftAt != nil else { return }
                guard !self.session.isStreaming else {
                    self.restartWhenAnswered()
                    return
                }
                self.leftAt = .now
                self.schedule()
            }
        }
    }

    /// A new setting applies to the clock already running.
    private func observeSetting() {
        withObservationTracking {
            _ = preferences.idleReset
        } onChange: {
            Task { @MainActor [weak self] in
                self?.schedule()
                self?.observeSetting()
            }
        }
    }
}

/// What the pin says while the idle clock runs: "forgets in 28m".
enum ForgetCountdown {
    /// Whole minutes, rounded up, so the last minute reads 1m; an hour or more in hours.
    static func duration(remaining: TimeInterval) -> String {
        let minutes = wholeMinutes(remaining)
        guard minutes >= 60 else { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func text(remaining: TimeInterval) -> String {
        "forgets in \(duration(remaining: remaining))"
    }

    /// The same, for VoiceOver and the tooltip: "28 minutes".
    static func spoken(remaining: TimeInterval) -> String {
        let minutes = wholeMinutes(remaining)
        if minutes >= 60, minutes % 60 == 0 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// Rounded up, with half a second of slack so a timeline entry landing on a minute reads that minute.
    private static func wholeMinutes(_ remaining: TimeInterval) -> Int {
        max(1, Int(((remaining - 0.5) / 60).rounded(.up)))
    }

    /// The moments the countdown changes: now, then each whole minute before the deadline. Without a deadline,
    /// nothing after now.
    struct Schedule: TimelineSchedule {
        let deadline: Date?

        func entries(from start: Date, mode: TimelineScheduleMode) -> [Date] {
            guard let deadline, deadline > start else { return [start] }
            let minutes = Int(deadline.timeIntervalSince(start) / 60)
            let changes = (0...minutes).reversed()
                .map { deadline.addingTimeInterval(-Double($0) * 60) }
                .filter { $0 > start }
            return [start] + changes
        }
    }
}

/// The pin, which keeps the window open when you click elsewhere (⌘P). While a pinned window waits on the screen
/// with a chat in it and you are away, the idle clock (`IdleClock`) runs, and the pin grows into a capsule that
/// counts down to the moment the chat moves on, so a fresh start is never a surprise.
struct PinButton: View {
    let preferences: Preferences
    /// When the chat moves on, while the clock runs and there is a chat to see go.
    let forgetsAt: Date?
    /// An anonymous chat is forgotten; any other goes to Recent Chats.
    let isAnonymous: Bool

    var body: some View {
        TimelineView(ForgetCountdown.Schedule(deadline: forgetsAt)) { context in
            button(remaining: forgetsAt.map { $0.timeIntervalSince(context.date) })
        }
        .animation(.smooth(duration: 0.25), value: forgetsAt)
    }

    private func button(remaining: TimeInterval?) -> some View {
        let isPinned = preferences.isPinned
        return Button { preferences.isPinned.toggle() } label: {
            HStack(spacing: 0) {
                if let remaining {
                    Text(ForgetCountdown.text(remaining: remaining))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .padding(.leading, 12)
                        .transition(.opacity)
                }
                // The symbol turns, never the glass around it.
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isPinned ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                    .rotationEffect(.degrees(45))
                    .frame(width: 32, height: 32)
                    .contentTransition(.symbolEffect(.replace))
            }
            .glassEffect(isPinned ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("p")
        .help(help(remaining: remaining))
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
        .accessibilityValue(remaining.map { "\(fate) in \(ForgetCountdown.spoken(remaining: $0))" } ?? "")
    }

    private var fate: String {
        isAnonymous ? "Forgets this chat" : "Moves this chat to Recent Chats"
    }

    private func help(remaining: TimeInterval?) -> String {
        let pin = preferences.isPinned ? "Unpin: close when clicking elsewhere (⌘P)" : "Pin: stay open when clicking elsewhere (⌘P)"
        guard let remaining else { return pin }
        return "\(fate) in \(ForgetCountdown.spoken(remaining: remaining)) unless you come back to it. \(pin)"
    }
}
