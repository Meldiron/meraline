import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The answers torn off into the note, as a pile: the one in front shows, the edges of the next two peek out under
/// it, and the count badge in its header brings the next one forward, so you flip through them without opening the
/// window. The pile counts from its top, as a pile does: the answer torn off last is 1. In memory only, like the
/// note.
nonisolated struct NoteStack: Equatable, Sendable {
    struct Note: Identifiable, Equatable, Sendable {
        let id: UUID
        let answer: String
        let question: String
        /// The chat's workspace, which an agent's relative paths in the answer start from; nil for an LLM's.
        let workspace: URL?
    }

    /// Where a step through the pile goes.
    enum Step: Equatable, Sendable {
        /// The note behind the front one, and after the last, the first again.
        case next
        case previous

        /// The step a key press asks for while the note has the keyboard: ⌃⇥ and ⇧⌘] for the next note, ⌃⇧⇥ and
        /// ⇧⌘[ for the one before, as tabs have them. `characters` keeps Shift, so ] comes as }.
        init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) {
            let pressed = modifiers.intersection([.command, .shift, .option, .control])
            switch (pressed, keyCode, characters) {
            case ([.control], UInt16(kVK_Tab), _), ([.command, .shift], _, "}"), ([.command, .shift], _, "]"): self = .next
            case ([.control, .shift], UInt16(kVK_Tab), _), ([.command, .shift], _, "{"), ([.command, .shift], _, "["): self = .previous
            default: return nil
            }
        }
    }

    /// How many of the notes behind the front one peek out under it.
    static let peekingLimit = 2

    /// Newest first.
    private(set) var notes: [Note] = []
    /// Which of `notes` is in front.
    private(set) var frontIndex = 0

    var count: Int { notes.count }
    var isEmpty: Bool { notes.isEmpty }
    var front: Note? { notes.isEmpty ? nil : notes[frontIndex] }

    /// The front note's place from the top of the pile: 1 for the answer torn off last.
    var position: Int { frontIndex + 1 }

    /// The count badge, "2/3", or nil while the pile is a single note.
    var badge: String? { count > 1 ? "\(position)/\(count)" : nil }

    /// The notes behind the front one that peek out, in the order they come forward.
    var peeking: [Note] {
        guard count > 1 else { return [] }
        return (1...min(count - 1, Self.peekingLimit)).map { notes[(frontIndex + $0) % count] }
    }

    /// Puts an answer on top of the pile, in front. An answer already in the pile comes forward instead of a copy.
    mutating func add(answer: String, question: String, workspace: URL? = nil) {
        if let index = notes.firstIndex(where: { $0.answer == answer && $0.question == question }) {
            frontIndex = index
            return
        }
        notes.insert(Note(id: UUID(), answer: answer, question: question, workspace: workspace), at: 0)
        frontIndex = 0
    }

    mutating func take(_ step: Step) {
        guard count > 1 else { return }
        switch step {
        case .next: frontIndex = (frontIndex + 1) % count
        case .previous: frontIndex = (frontIndex + count - 1) % count
        }
    }

    /// Takes the front note out of the pile, and the one behind it comes forward.
    mutating func removeFront() {
        guard !notes.isEmpty else { return }
        notes.remove(at: frontIndex)
        if frontIndex >= notes.count { frontIndex = 0 }
    }
}

/// Where the cards of a pile lie: the front one, then each note behind it a little narrower and lower, so its
/// bottom edge shows under the one in front.
nonisolated enum NoteStackGeometry {
    /// How far each note behind shows under the one in front of it.
    static let peek: CGFloat = 7
    /// How much narrower each note behind is than the one in front of it, on each side.
    static let inset: CGFloat = 12
    static let cornerRadius: CGFloat = 20

    /// The room under the front card for `depth` notes peeking out.
    static func room(for depth: CGFloat) -> CGFloat { depth * peek }

    /// The card at `index`, 0 for the front one, in `rect`, which holds the front card and the room under it for
    /// `depth` notes. One further back than `depth` lies under the last that shows, hidden.
    static func card(_ index: Int, in rect: CGRect, depth: CGFloat) -> Path {
        let front = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, rect.height - room(for: depth)))
        let lowered = min(CGFloat(index), depth) * peek
        let card = front.insetBy(dx: CGFloat(index) * inset, dy: 0).offsetBy(dx: 0, dy: lowered)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: card)
    }

    /// Everything the pile covers, for its shadow.
    static func outline(in rect: CGRect, depth: CGFloat) -> Path {
        (1...NoteStack.peekingLimit).reduce(card(0, in: rect, depth: depth)) { $0.union(card($1, in: rect, depth: depth)) }
    }

    /// What shows of the card at `index`: all of it but what the cards in front of it cover.
    static func edge(_ index: Int, in rect: CGRect, depth: CGFloat) -> Path {
        let inFront = (1..<max(index, 1)).reduce(card(0, in: rect, depth: depth)) { $0.union(card($1, in: rect, depth: depth)) }
        return card(index, in: rect, depth: depth).subtracting(inFront)
    }
}

/// The edge of a note behind the front one, peeking out under it.
nonisolated struct PeekingEdge: Shape {
    let index: Int
    var depth: CGFloat

    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        NoteStackGeometry.edge(index, in: rect, depth: depth)
    }
}

/// The whole pile's outline, which its shadow falls from.
nonisolated struct NoteStackOutline: Shape {
    var depth: CGFloat

    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        NoteStackGeometry.outline(in: rect, depth: depth)
    }
}

/// The edges of the notes behind the front one, in glass, drawn behind its card over the room the card leaves under
/// itself. There are always as many as can peek out, and the pile's depth lowers each into view or tucks it away
/// under the one in front, so no glass is inserted or taken out while the pile changes.
struct PeekingEdges: View {
    let depth: CGFloat

    var body: some View {
        ZStack {
            ForEach(1...NoteStack.peekingLimit, id: \.self) { index in
                Color.clear
                    .glassEffect(.regular, in: PeekingEdge(index: index, depth: depth))
                    .opacity(min(max(depth - CGFloat(index - 1), 0), 1))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The count badge in a pile's header: which note is in front and how many there are, as "2/3". A click brings the
/// next one forward, and a click with ⇧ the one before.
struct NoteStackBadge: View {
    let stack: NoteStack
    let step: (NoteStack.Step) -> Void

    var body: some View {
        Button {
            step(NSEvent.modifierFlags.contains(.shift) ? .previous : .next)
        } label: {
            Text(stack.badge ?? "")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(stack.position)))
                .padding(.horizontal, 9)
                .frame(minWidth: 26)
                .frame(height: 26)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Next Note (⌃⇥)")
        .accessibilityLabel("Note \(stack.position) of \(stack.count)")
        .accessibilityHint("Shows the next note")
        .accessibilityAction(named: "Previous Note") { step(.previous) }
    }
}
