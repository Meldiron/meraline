import SwiftUI

/// The capsule under the card's bottom right, lined up with the footer's actions: how long the open chat has
/// before it goes, workspace and all (`ChatSession.chatLifetime`), in minutes and then, in its last one, seconds.
/// It takes no click; the buttons to its left give the chat `extraMinutes` more, and the capsule shines as they
/// do (`Shine`). Neutral glass, like the buttons above the card, until it reads `warningMinutes` or less: then it
/// looks like the mode toggle's chosen segment, a pink symbol and a semibold label in pink-tinted glass.
struct ChatTimer: View {
    let expiresAt: Date
    let addTime: (_ minutes: Int) -> Void

    /// What the buttons beside the timer add, in minutes.
    static let extraMinutes = [5, 30]

    /// How many times the buttons added time, for the capsule to shine at each.
    @State private var additions = 0

    var body: some View {
        HStack(spacing: 10) {
            GlassEffectContainer {
                HStack(spacing: 10) {
                    ForEach(Self.extraMinutes, id: \.self) { minutes in
                        Button {
                            // Animated, so the time left rolls up to its new minutes.
                            withAnimation(.snappy(duration: 0.4)) {
                                addTime(minutes)
                                additions += 1
                            }
                        } label: {
                            Text("+\(minutes) min")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: Announcements.size)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .hoverTip("Give this chat \(minutes) more minutes")
                        .accessibilityLabel("Add \(minutes) minutes")
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = Self.seconds(until: expiresAt, now: context.date)
                KeyframeAnimator(initialValue: Shine(), trigger: additions) { shine in
                    TimeLeft(seconds: seconds, shine: shine, additions: additions)
                } keyframes: { _ in
                    Shine.keyframes
                }
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    /// The capsule turns pink once it reads this many minutes left, or less.
    static let warningMinutes = 5

    /// "30 min left" down to "1 min left", then "59 s left" down to "1 s left".
    static func remaining(until deadline: Date, now: Date) -> String {
        label(for: seconds(until: deadline, now: now))
    }

    /// Whether the capsule reads `warningMinutes` or less, "5 min left" included.
    static func isRunningOut(until deadline: Date, now: Date) -> Bool {
        isRunningOut(seconds(until: deadline, now: now))
    }

    fileprivate static func label(for seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min left" : "\(max(1, seconds)) s left"
    }

    fileprivate static func isRunningOut(_ seconds: Int) -> Bool {
        seconds / 60 <= warningMinutes
    }

    private static func seconds(until deadline: Date, now: Date) -> Int {
        Int(max(0, deadline.timeIntervalSince(now)).rounded(.up))
    }
}

/// How the time left shines when time is added: the capsule swells a little and settles with a spring, its glass
/// flushes pink and fades back, and a highlight sweeps across it, left to right. Each value runs on its own track.
private struct Shine {
    /// The capsule's size, 1 at rest.
    var scale = 1.0
    /// How pink the glass and the symbol are, 0 at rest and 1 at the peak.
    var glow = 0.0
    /// Where the highlight is across the capsule, from `sweepStart` to `sweepEnd`, where it is out of sight.
    var sweep = Shine.sweepEnd

    static let sweepStart = -0.4
    static let sweepEnd = 1.4

    @KeyframesBuilder<Shine>
    static var keyframes: some Keyframes<Shine> {
        KeyframeTrack(\.scale) {
            SpringKeyframe(1.09, duration: 0.16, spring: .snappy)
            SpringKeyframe(1, duration: 0.6, spring: .bouncy(duration: 0.5, extraBounce: 0.1))
        }
        KeyframeTrack(\.glow) {
            CubicKeyframe(1, duration: 0.14)
            CubicKeyframe(1, duration: 0.3)
            CubicKeyframe(0, duration: 0.8)
        }
        KeyframeTrack(\.sweep) {
            MoveKeyframe(sweepStart)
            LinearKeyframe(sweepStart, duration: 0.06)
            CubicKeyframe(sweepEnd, duration: 0.62)
        }
    }
}

/// The capsule of the time left, at one moment of its `Shine`. The scale goes on a glass container of its own,
/// since a scale inside a shared one never reaches the glass.
private struct TimeLeft: View {
    let seconds: Int
    let shine: Shine
    let additions: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunningOut: Bool { ChatTimer.isRunningOut(seconds) }

    var body: some View {
        let label = ChatTimer.label(for: seconds)
        GlassEffectContainer {
            HStack(spacing: 5) {
                symbol
                Text(label)
                    .font(.system(size: 12, weight: isRunningOut ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isRunningOut ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText(value: Double(seconds)))
            }
            .padding(.horizontal, 12)
            .frame(height: Announcements.size)
            .overlay { highlight }
            .glassEffect(glass, in: .capsule)
            .animation(.easeInOut(duration: 0.4), value: isRunningOut)
        }
        .scaleEffect(reduceMotion ? 1 : shine.scale)
        .hoverTip("This chat and its files go when the time runs out, never sooner than \(Int(ChatSession.chatLifetime / 60)) minutes after its last message.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time left for this chat")
        .accessibilityValue(label)
    }

    /// Pink while the time runs out, and brighter at the peak of a shine.
    private var glass: Glass {
        let tint = max(isRunningOut ? 0.22 : 0, 0.3 * shine.glow)
        return .regular.tint(.meralinePink.opacity(tint))
    }

    /// The timer, pink while the time runs out, and flushing pink with the glass as it shines.
    private var symbol: some View {
        let rest: AnyShapeStyle = isRunningOut ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary)
        return Image(systemName: "timer")
            .foregroundStyle(rest)
            .overlay {
                Image(systemName: "timer")
                    .foregroundStyle(Color.meralinePink)
                    .opacity(isRunningOut ? 0 : shine.glow)
            }
            .symbolEffect(.bounce.up, options: .speed(1.4), value: additions)
            .font(.system(size: 12, weight: .medium))
    }

    /// A band of light slanting across the capsule. Always in the view tree, clear at rest, so nothing is inserted
    /// beside the glass.
    private var highlight: some View {
        let isSweeping = !reduceMotion && shine.sweep > Shine.sweepStart && shine.sweep < Shine.sweepEnd
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.3), location: 0.5),
                .init(color: .white.opacity(0), location: 1)
            ],
            startPoint: UnitPoint(x: shine.sweep - 0.22, y: 0),
            endPoint: UnitPoint(x: shine.sweep + 0.22, y: 1)
        )
        .blendMode(.plusLighter)
        .clipShape(.capsule)
        .opacity(isSweeping ? 1 : 0)
        .allowsHitTesting(false)
    }
}
