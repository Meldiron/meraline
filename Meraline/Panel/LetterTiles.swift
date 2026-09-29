import SwiftUI

/// A round's letters, each in a glass bubble, and a button that shuffles them while you look for your word.
/// The order is only how they show, in this view's state: the round keeps its letters as they were drawn.
struct LetterTiles: View {
    let letters: [String]
    /// Whether the shuffle button shows, while the round waits for your word.
    let shuffles: Bool

    /// The slot each letter sits in, by its index in `letters`; empty for the order they were drawn in.
    @State private var slots: [Int] = []
    /// The slots before the last shuffle, which each letter arcs away from.
    @State private var previous: [Int] = []
    @State private var shuffleCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size: CGFloat = 36
    static let spacing: CGFloat = 8
    private static var pitch: CGFloat { size + spacing }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .leading) {
                ForEach(letters.indices, id: \.self) { index in
                    LetterTile(
                        letter: letters[index],
                        slot: Double(slot(of: index, in: slots)),
                        from: Double(slot(of: index, in: previous)),
                        to: Double(slot(of: index, in: slots)),
                        lift: reduceMotion ? 0 : 1
                    )
                    .zIndex(slot(of: index, in: slots) > slot(of: index, in: previous) ? 1 : 0)
                    .animation(hop(to: slot(of: index, in: slots)), value: shuffleCount)
                }
            }
            .frame(width: CGFloat(letters.count) * Self.pitch - Self.spacing, height: Self.size, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Letters")
            .accessibilityValue(shown.joined(separator: " "))

            if shuffles {
                Button(action: shuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.bounce, value: shuffleCount)
                        .frame(width: Self.size, height: Self.size)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .hoverTip("Shuffle Letters")
                .accessibilityLabel("Shuffle Letters")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.smooth(duration: 0.2), value: shuffles)
        .onChange(of: letters) {
            slots = []
            previous = []
        }
    }

    /// The letters in the order they show.
    private var shown: [String] {
        letters.indices.sorted { slot(of: $0, in: slots) < slot(of: $1, in: slots) }.map { letters[$0] }
    }

    private func slot(of index: Int, in slots: [Int]) -> Int {
        slots.indices.contains(index) ? slots[index] : index
    }

    /// A spring for each letter, starting a moment after the one to its left, so the shuffle runs across the row.
    private func hop(to slot: Int) -> Animation {
        guard !reduceMotion else { return .smooth(duration: 0.3) }
        return .spring(duration: 0.55, bounce: 0.3).delay(Double(slot) * 0.025)
    }

    /// Deals the letters into new slots, in an order that reads differently from the one showing.
    private func shuffle() {
        let before = shown
        var next = Array(letters.indices)
        for _ in 0..<10 {
            next.shuffle()
            if next.map({ letters[$0] }) != before { break }
        }
        // `next` lists the letters slot by slot; `slots` wants each letter's slot.
        var dealt = Array(repeating: 0, count: letters.count)
        for (slot, index) in next.enumerated() { dealt[index] = slot }
        previous = letters.indices.map { slot(of: $0, in: slots) }
        slots = dealt
        shuffleCount += 1
    }
}

/// One letter in its bubble, laid out from `slot`, which SwiftUI springs from the old slot to the new one.
/// On the way it arcs up when it moves right and down when it moves left, so letters trading places pass each
/// other instead of sliding through; it swells a little over the row and shrinks a little under it, as if in
/// front and behind. Glass is never rotated.
private struct LetterTile: View, Animatable {
    let letter: String
    var slot: Double
    let from: Double
    let to: Double
    /// How high the arc goes, from 0 (a straight slide) to 1.
    let lift: Double

    var animatableData: Double {
        get { slot }
        set { slot = newValue }
    }

    /// How far along its move the letter is, 0 to 1; a spring's overshoot stays at the end.
    private var progress: Double {
        guard to != from else { return 1 }
        return min(max((slot - from) / (to - from), 0), 1)
    }

    /// Farther moves arc higher, up to a little over half a bubble.
    private var arc: Double {
        let distance = to - from
        guard distance != 0 else { return 0 }
        let height = 8 + min(abs(distance), 4) * 3
        return sin(progress * .pi) * height * lift * (distance > 0 ? -1 : 1)
    }

    var body: some View {
        Text(letter)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: LetterTiles.size, height: LetterTiles.size)
            .glassEffect(.regular, in: .circle)
            .scaleEffect(1 - 0.12 * arc / 20)
            .offset(x: slot * (LetterTiles.size + LetterTiles.spacing), y: arc)
    }
}
