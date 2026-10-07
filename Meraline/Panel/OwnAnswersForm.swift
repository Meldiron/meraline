import SwiftUI

/// What the form for your own answers holds while it is open (see `OwnAnswersForm`): the text in its field, and the
/// way of writing chosen while the text has no separator to say which. The text says: `<` anywhere makes levels in
/// order and `/` a set to pick one from (see `DecisionAnswers.parse`), so typing either moves the toggle, and the
/// toggle rewrites the separators in the text.
nonisolated struct OwnAnswersDraft: Equatable, Sendable {
    var text: String
    /// The way chosen for a text with neither separator: by the toggle, or ↑ and ↓.
    var prefersOrdered: Bool

    init(text: String) {
        self.text = text
        prefersOrdered = text.contains("<")
    }

    /// Levels in order, with `<`, rather than a set to pick one from, with `/`.
    var isOrdered: Bool {
        if text.contains("<") { return true }
        if text.contains("/") { return false }
        return prefersOrdered
    }

    /// The answers the text reads as, or nil while it reads as none (see `problem`).
    var answers: DecisionAnswers? { DecisionAnswers.parse(text) }

    /// Why the text reads as no answers yet, or nil once it does.
    var problem: String? { DecisionAnswers.problem(in: text, ordered: isOrdered) }

    /// Under the field: the answers in a line once they read, else what is missing.
    var status: String { answers?.summary ?? problem ?? "" }

    /// Under the field, for a form beside `others`, the other lists of your own: that the answers are one of them
    /// already, when they are, which the button then uses rather than writing them twice.
    func status(beside others: [String]) -> String {
        guard let answers, others.contains(answers.text) else { return status }
        return "\(answers.summary) You have these already."
    }

    /// The other way of writing: ↑ or ↓ in the field.
    mutating func switchOrder() { choose(ordered: !isOrdered) }

    /// One way of writing: the separators in the text change with it, `/` to `<` or back, spaced as
    /// `DecisionAnswers.text` writes them once the answers read, and a text with neither keeps the choice for its hint.
    mutating func choose(ordered: Bool) {
        prefersOrdered = ordered
        guard isOrdered != ordered else { return }
        if let answers {
            text = DecisionAnswers(options: answers.options, isOrdered: ordered).text
        } else {
            let from: Character = ordered ? "/" : "<"
            let to: Character = ordered ? "<" : "/"
            text = String(text.map { $0 == from ? to : $0 })
        }
    }
}

/// In the answers panel's list's place (see `PanelAction.editor`, `ActionPanelRequest.editing`): a list of answers of
/// your own, new or one to edit, written in a field of the panel's own kind. A toggle above it says how they are
/// written, a set to pick one from with `/` between them or levels in order with `<`, each explained under it; ↑ and
/// ↓ switch it, as the arrows move a list's selection, and typing either separator switches it too. Under the
/// field, the answers in a line once they read, or what is missing, and when another list has them already, so
/// it says. Return takes them, as the form's button does (Add and Use, Save and Use), and Esc goes back to the
/// list, as Back does. The toggle's thumb is a flat tint, not glass, like the row highlights around it: the form
/// fades in and out inside the panel's glass.
struct OwnAnswersForm: View {
    let editor: ActionEditor
    let back: () -> Void

    @State private var draft: OwnAnswersDraft
    /// Requests for the field to take the keyboard again, after a click on the toggle.
    @State private var fieldFocus = 0
    @State private var hovered: String?

    init(editor: ActionEditor, back: @escaping () -> Void) {
        self.editor = editor
        self.back = back
        _draft = State(initialValue: OwnAnswersDraft(text: editor.text))
    }

    /// About how tall the form is, for the panel to choose which way to open (see `ActionPanel.estimatedHeight`).
    static let estimatedHeight: CGFloat = 300
    private static let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editor.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 34, alignment: .bottomLeading)
                .padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    OrderToggle(isOrdered: draft.isOrdered) { ordered in
                        draft.choose(ordered: ordered)
                        fieldFocus += 1
                    }
                    Spacer(minLength: 8)
                    KeyCaps(keys: ["↑", "↓"], size: 18)
                        .help("↑ and ↓ switch between the two")
                }
                Text(DecisionAnswers.explanation(ordered: draft.isOrdered))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                field
                let status = draft.status(beside: editor.others)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(draft.answers == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .accessibilityLabel(status)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            Divider()
            VStack(spacing: 0) {
                row(editor.button, keys: ActionShortcut.returnKey.keycaps, isEnabled: draft.answers != nil, isPrimary: true, action: submit)
                row("Back", keys: ActionShortcut.escape.keycaps, isEnabled: true, isPrimary: false, action: back)
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: draft.isOrdered)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your own answers")
    }

    /// The field, with the symbol of what the answers read as before it (see `DecisionAnswers.symbol`).
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: draft.answers?.symbol ?? (draft.isOrdered ? "list.number" : "list.bullet"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            ActionSearchField(
                text: $draft.text,
                prompt: draft.isOrdered ? "Low < Medium < High" : "Billing / Technical / Sales",
                focus: fieldFocus,
                keepsCursorAtEnd: true,
                onMove: { _ in draft.switchOrder() },
                onSubmit: submit,
                onCancel: back
            )
            .frame(height: 20)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 9))
        .accessibilityLabel("Answers")
    }

    /// A row like the confirmation's: the form's button, lit while the answers read, since Return takes them, and
    /// faded until then; and Back.
    private func row(_ title: String, keys: [String], isEnabled: Bool, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                KeyCaps(keys: keys)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background {
                if isEnabled, isPrimary || hovered == title {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.primary.opacity(0.08))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.smooth(duration: 0.18), value: isEnabled)
        .onHover { inside in
            if inside { hovered = title } else if hovered == title { hovered = nil }
        }
        .help(isEnabled ? title : "Write two or more answers first")
    }

    private func submit() {
        guard let answers = draft.answers else { return }
        editor.save(answers.text)
    }
}

/// Two segments in a capsule: a set to pick one from, `/`, and levels in order, `<`, each its separator and its
/// name. The chosen one carries a pink pill, a flat tint rather than glass (see `OwnAnswersForm`), which slides
/// across when the way changes, as the mode toggle's does.
private struct OrderToggle: View {
    let isOrdered: Bool
    let choose: (Bool) -> Void

    @Namespace private var thumb
    @State private var hovered: Bool?

    var body: some View {
        HStack(spacing: 2) {
            segment(ordered: false, title: "Pick one")
            segment(ordered: true, title: "Levels in order")
        }
        .padding(3)
        .background(Capsule().fill(.primary.opacity(0.06)))
        .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: isOrdered)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How the answers are written")
    }

    private func segment(ordered: Bool, title: String) -> some View {
        let isOn = isOrdered == ordered
        return Button { choose(ordered) } label: {
            HStack(spacing: 6) {
                Text(ordered ? "<" : "/")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                Text(title)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background {
                if isOn {
                    Capsule()
                        .fill(Color.meralinePink.opacity(0.2))
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                } else if hovered == ordered {
                    Capsule().fill(.primary.opacity(0.07))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = ordered } else if hovered == ordered { hovered = nil }
        }
        .help(ordered ? "Levels in order, with < between them" : "A set to pick one from, with / between them")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
