import AppKit
import SwiftUI

/// What Jev decided, in the answer's place (see `Decision`): a glass disc with a check on green glass for Yes, a
/// cross on red for No, a question mark on neutral glass for Not Sure, or, for one of your own answers (a choice or
/// a score), a check tinted by how sure Jev is — amber when it is only moderately sure, green when it is very sure.
/// A ring around the disc is how sure Jev is, and beside it the answer and “82% confident”. Under them, every
/// answer with its probability — or, for answers in order (Jev's `score`), a scale that lays the levels out first
/// to last with a marker where Jev placed the text, between two levels when it isn't sure, coloured by that same
/// confidence. The check, the cross, the marker, and the words carry the meaning, so the colors are only a help, as
/// in Show What Changed.
///
/// A colour that follows how sure Jev is, for a choice or a score: red at the low end, amber in the middle, green
/// when very sure — a decision shows the low end as Not Sure instead, so choices in practice run amber to green.
private func confidenceColor(_ confidence: Double) -> Color {
    let c = min(max(confidence, 0), 1)
    let low = NSColor.removedText, mid = NSColor.systemOrange, high = NSColor.addedText
    let blended = c >= 0.5 ? mid.blended(withFraction: (c - 0.5) * 2, of: high)
                           : low.blended(withFraction: c * 2, of: mid)
    return Color(nsColor: blended ?? high)
}
struct DecisionCard: View {
    let decision: Decision
    /// Under this confidence the card says Not Sure (see `Preferences.unsureBelow`).
    let unsureBelow: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How much of the ring has been drawn, from none as the card appears to all of it.
    @State private var ringDrawn = 0.0

    static let discSize: CGFloat = 56

    private var verdict: Decision.Verdict { decision.verdict(unsureBelow: unsureBelow) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                disc
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            if decision.isOrdered {
                ScaleRow(decision: decision, progress: ringDrawn, color: tint)
            } else {
                ProbabilityRow(decision: decision)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.7).delay(0.1)) { ringDrawn = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(decision.summary(unsureBelow: unsureBelow))
        .accessibilityValue(decision.options.map { "\($0.label) \(Decision.percent($0.probability))" }.joined(separator: ", "))
    }

    /// The disc: tinted glass, the symbol, and the ring of confidence around it, a ring that is drawn once as
    /// the card appears and stays put with Reduce Motion.
    private var disc: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: decision.confidence * ringDrawn)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: Self.discSize - 12, height: Self.discSize - 12)
                .glassEffect(tint.map { .regular.tint($0.opacity(0.3)) } ?? .regular, in: .circle)
        }
        .frame(width: Self.discSize, height: Self.discSize)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch verdict {
        case .yes, .chosen: "checkmark"
        case .no: "xmark"
        case .unsure: "questionmark"
        }
    }

    /// Green for Yes and red for No, deeper shades on light glass (see `NSColor.addedText`); for one of your own
    /// answers, the colour of how sure Jev is; nothing while it is Not Sure.
    private var tint: Color? {
        switch verdict {
        case .yes: Color(nsColor: .addedText)
        case .no: Color(nsColor: .removedText)
        case .chosen: confidenceColor(decision.confidence)
        case .unsure: nil
        }
    }

    private var symbolColor: AnyShapeStyle {
        tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)
    }

    private var ringColor: AnyShapeStyle {
        tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary)
    }

    private var title: String {
        verdict == .unsure ? "Not sure" : decision.chosen.label
    }

    private var subtitle: String {
        let sure = "\(Decision.percent(decision.confidence)) confident"
        return verdict == .unsure ? "Leaning \(decision.chosen.label) · \(sure)" : sure
    }
}

/// Every answer with the probability Jev gives it, in the answers' order, as quiet capsules in a row that wraps:
/// the chosen one in the primary color and semibold, the rest secondary.
private struct ProbabilityRow: View {
    let decision: Decision

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(decision.options) { option in
                let isChosen = option.label == decision.chosen.label
                HStack(spacing: 5) {
                    Text(option.label)
                        .font(.system(size: 12, weight: isChosen ? .semibold : .medium))
                        .foregroundStyle(isChosen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    Text(Decision.percent(option.probability))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.primary.opacity(isChosen ? 0.09 : 0.04), in: .capsule)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(option.label) \(Decision.percent(option.probability))")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(decision.isOrdered ? "Levels" : "Answers")
    }
}

/// The levels of a `score` decision laid out first to last along a track, with a filled meter and a marker where
/// Jev placed the text (its `score`, which sits between two levels when Jev isn't sure), and each level's
/// probability beneath it, the chosen one emphasized. Unlike the choice row's even capsules, it shows the order
/// and how far along it the text landed. Neutral graphite, like the rest of the card.
private struct ScaleRow: View {
    let decision: Decision
    /// How far the meter is drawn, from none as the card appears to all of it, in step with the disc's ring.
    let progress: Double
    /// The colour of how sure Jev is, for the meter and the marker; nil (neutral) while it is Not Sure.
    let color: Color?

    private var meterColor: Color { color ?? .primary }

    /// The marker's diameter and the track's height.
    private static let marker: CGFloat = 13
    private static let track: CGFloat = 6

    private var count: Int { decision.options.count }

    /// Where the text sits in level space: 0 at the first level, `count - 1` at the last, from Jev's score or, when
    /// it gives none, the chosen level's place.
    private var position: Double {
        let chosen = decision.options.firstIndex { $0.label == decision.chosen.label } ?? 0
        return min(max(decision.score ?? Double(chosen), 0), Double(max(count - 1, 0)))
    }

    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { geo in
                let width = geo.size.width
                let cell = width / CGFloat(max(count, 1))
                // Levels sit at the centre of their cell, so the ends never spill past the track; the marker
                // follows the same mapping, drawing in from the left in step with the disc's ring.
                let markerX = cell * (CGFloat(position) + 0.5)
                let drawn = markerX * progress
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.08))
                        .frame(height: Self.track)
                    Capsule()
                        .fill(meterColor.opacity(color == nil ? 0.35 : 0.55))
                        .frame(width: drawn, height: Self.track)
                    ForEach(Array(decision.options.enumerated()), id: \.offset) { index, _ in
                        Circle()
                            .fill(.primary.opacity(0.18))
                            .frame(width: 3, height: 3)
                            .offset(x: cell * (CGFloat(index) + 0.5) - 1.5)
                    }
                    Circle()
                        .fill(meterColor)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .frame(width: Self.marker, height: Self.marker)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                        .offset(x: drawn - Self.marker / 2)
                }
                .frame(width: width, height: geo.size.height)
            }
            .frame(height: Self.marker)

            HStack(spacing: 0) {
                ForEach(decision.options) { option in
                    let isChosen = option.label == decision.chosen.label
                    VStack(spacing: 1) {
                        Text(option.label)
                            .font(.system(size: 11, weight: isChosen ? .semibold : .medium))
                            .foregroundStyle(isChosen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        Text(Decision.percent(option.probability))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(isChosen ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale from \(decision.options.first?.label ?? "") to \(decision.options.last?.label ?? "")")
        .accessibilityValue(decision.options.map { "\($0.label) \(Decision.percent($0.probability))" }.joined(separator: ", "))
    }
}

/// The answers the next question picks from, at the games' place under the input while Decision mode is on (see
/// `DecisionAnswers`): the ones typed after the question, or Settings' default. Neutral glass, no click.
struct DecisionAnswersBadge: View {
    let answers: DecisionAnswers

    private var symbol: String {
        switch answers.kind {
        case .yesNo: "circle.lefthalf.filled"
        case .choice: "list.bullet"
        case .score: "list.number"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(answers.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        // Its label's width, up to a cap, whatever the row offers: a flexible frame alone stretched it to the cap.
        .frame(maxWidth: 260)
        .fixedSize(horizontal: true, vertical: false)
        .glassEffect(.regular, in: .capsule)
        .help(answers.isOrdered ? "The levels the model places the text along" : "The answers the model picks from")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answers: \(answers.text)")
    }
}

/// Between the input and the mode row while a decision has no text to decide about: what to add, and a button
/// that puts a card to write it in where the row was (see `TypedStateCard`). Glass like the setup row, with the
/// faint pink of the panel's buttons.
struct DecisionStateRow: View {
    let write: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.quote")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("What’s the context for this decision?")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add the text you selected or copied, or write it here — it’s optional.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Write It", action: write)
                .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Between the cards and the mode row, after a click on the scope switch under the input (`DecisionScopeToggle`):
/// the chosen scope and what it decides about, the whole text too when it was switched back to, so the switch
/// explains itself once it is used and never before. It goes with the question, with the chat, or at its cross
/// (see `ChatSession.explainedScope`). Glass like the row that asks for context.
struct DecisionScopeNote: View {
    let scope: DecisionScope
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: scope.symbol)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(scope.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(scope.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CardButton(symbol: "xmark", label: "Hide what the scope decides about", action: dismiss)
                .help("Hide")
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(scope.title): \(scope.explanation)")
    }
}

/// Text written in the window itself, opened with Tab in any mode (or Decision's Write It row, Add Text in the
/// sparkle's panel, or a preset put in an empty draft), between the input and the row under it: a note of
/// context for an LLM or agent, or the text a decision is about. Like a selected text's card: a header that
/// counts its words, a field of a few lines that grows with the text, and a cross. It goes with the question as a
/// text of its own, quoted in the conversation as Context, like a selection, and ⌘Return sends from it (see
/// `PanelController`). Whoever opens it gives it the keyboard (see `PanelLayout.stateFocusRequest`). In Decision
/// mode its header has a Live switch (`LiveSwitch`): on, the card decides as you type, and the answers show on
/// glass capsules under the text (`LiveDecisionStrip`, see `LiveDecisions`).
struct TypedStateCard: View {
    @Binding var text: String
    /// Decision mode, where the text is what Jev decides about; in the other modes it goes with the question.
    var isDeciding = false
    /// The decisions made as you type, for the switch and the chips, in Decision mode.
    var live: LiveDecisions?
    /// Under this confidence a live decision says Not Sure (see `Preferences.unsureBelow`).
    var unsureBelow = Decision.defaultUnsureBelow
    /// Whether the card's editor has the keyboard, which the window hands it as the card opens.
    var isFocused: FocusState<Bool>.Binding
    var toggleLive: () -> Void = {}
    var togglePreset: (PromptPreset.ID) -> Void = { _ in }
    /// The plus on the input's capsule keeps its question; a kept question's capsule turns it on or off, and its
    /// cross removes it (see `KeptQuestion`).
    var keepLive: () -> Void = {}
    var toggleKept: (UUID) -> Void = { _ in }
    var removeKept: (UUID) -> Void = { _ in }
    let remove: () -> Void

    @State private var textHeight: CGFloat = 0

    private static let font = Font.system(size: 13)
    /// The field's height past which it scrolls.
    private static let tallest: CGFloat = 160
    /// The room above and below the text, the same for the editor, its placeholder, and the hidden copy that sizes it.
    private static let inset: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Context")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("· \(words) \(words == 1 ? "word" : "words")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if isDeciding, let live {
                    LiveSwitch(isOn: live.isOn, toggle: toggleLive)
                }
                CardButton(symbol: "xmark", label: "Leave out the context", action: remove)
                    .help("Leave it out")
            }
            .lineLimit(1)
            ZStack(alignment: .topLeading) {
                // The text laid out the way the editor lays it out, never drawn, so the editor fits it.
                Text(text.isEmpty ? " " : text)
                    .font(Self.font)
                    .lineSpacing(2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, Self.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }
                if text.isEmpty {
                    Text(isDeciding ? "Paste or type the text to decide about…" : "Paste or type text to send with your question…")
                        .font(Self.font)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, Self.inset)
                        .allowsHitTesting(false)
                }
                // The field fits its text, with a little room to spare, and scrolls only past its tallest, so no
                // scroll bar shows beside a line or two. The editor draws its first line at its very top (no inset of
                // its own, and content margins don't reach it), so it sits `inset` down, where the placeholder is;
                // the caret was otherwise a line's gap above the placeholder.
                TextEditor(text: $text)
                    .font(Self.font)
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(textHeight + 8 <= Self.tallest)
                    .tint(.meralinePink)
                    .focused(isFocused)
                    .frame(height: min(max(textHeight + 8, 40), Self.tallest) - Self.inset * 2)
                    .padding(.vertical, Self.inset)
            }
            .padding(.horizontal, 4)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 10))
            if isDeciding, let live, live.isOn {
                LiveDecisionStrip(live: live, unsureBelow: unsureBelow, togglePreset: togglePreset, keep: keepLive, toggleKept: toggleKept, removeKept: removeKept)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isDeciding ? "Context written for the decision" : "Context written for the question")
    }

    private var words: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// The Live switch in the Context card's header, in Decision mode: a bolt and the word, which turn pink and
/// semibold while the card decides as you type (see `LiveDecisions`), like the mode toggle's chosen segment.
/// Glass like the cross beside it.
private struct LiveSwitch: View {
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                Text("Live")
                    .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .glassEffect(isOn ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Stop deciding as you type" : "Decide as you type: the answers show here, without sending")
        .accessibilityLabel("Live decisions")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Under the Context card's text while Live is on (see `LiveDecisions`): a glass capsule for each question, the
/// input's first, then those kept from it, then Decision's presets, each with its answer once it comes: a check on
/// green glass for Yes, a cross on red for No, a question mark on plain glass for Not Sure, or a check on glass
/// tinted by how sure the model is of one of your own answers, as `DecisionCard`'s disc has them, then the answer
/// and how sure. A capsule that is on and waiting wears the pink of a chosen segment; one that is off is plain
/// glass with secondary text. A click on a preset's or a kept question's capsule turns it on or off; the plus on
/// the input's keeps its question (`keep`), which frees the input for the next, and the cross on a kept question's
/// removes it. Each capsule is a glass container of its own, so its fade reaches its glass, as the follow-ups' are,
/// and none rotates, so the glass never swells into a disc. The check, the cross, and the words carry the meaning;
/// the tints are only a help.
struct LiveDecisionStrip: View {
    let live: LiveDecisions
    /// Under this confidence a decision says Not Sure (see `Preferences.unsureBelow`).
    let unsureBelow: Double
    let togglePreset: (PromptPreset.ID) -> Void
    var keep: () -> Void = {}
    var toggleKept: (UUID) -> Void = { _ in }
    var removeKept: (UUID) -> Void = { _ in }

    @State private var hovered: LiveQuestion.ID?

    /// A capsule comes in and goes with its glass, since each has a container of its own.
    static let transition: AnyTransition = .opacity.combined(with: .scale(scale: 0.92))
    private static let height: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(live.questions) { question in
                    capsule(question)
                        .transition(Self.transition)
                }
            }
            if live.asksNothing {
                Text("Ask in the input, or turn on a preset, and the answer shows here as you type. The plus on a question keeps it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let failure = live.failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
        .animation(.smooth(duration: 0.2), value: live.questions)
        .animation(.smooth(duration: 0.25), value: live.answers)
        .animation(.smooth(duration: 0.2), value: live.pending)
        .animation(.smooth(duration: 0.2), value: live.failure)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live decisions")
    }

    /// One question's glass capsule: the input's with a plus to keep it, a kept question's with a cross to remove
    /// it, a preset's on its own; a click on a kept question's or a preset's label turns it on or off.
    private func capsule(_ question: LiveQuestion) -> some View {
        let answer = live.answer(for: question)
        let verdict = answer?.verdict(unsureBelow: unsureBelow)
        let isHovered = hovered == question.id
        return GlassEffectContainer {
            HStack(spacing: 0) {
                switch question.source {
                case .input:
                    label(question, answer: answer, verdict: verdict, trailsButton: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("The question in the input: \(question.title)")
                        .accessibilityValue(value(of: question))
                    Button(action: keep) {
                        trailing("plus", highlighted: isHovered)
                    }
                    .buttonStyle(.plain)
                    .help("Keep asking this: it stays as a question of its own, and the input is free for the next")
                    .accessibilityLabel("Keep asking this")
                case .kept(let id):
                    Button { toggleKept(id) } label: {
                        label(question, answer: answer, verdict: verdict, trailsButton: true)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(question.isOn ? "Stop asking “\(question.title)” as you type" : "Ask “\(question.title)” as you type")
                    .accessibilityLabel(question.title)
                    .accessibilityValue(value(of: question))
                    .accessibilityAddTraits(question.isOn ? .isSelected : [])
                    Button { removeKept(id) } label: {
                        trailing("xmark", highlighted: isHovered)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the question")
                    .accessibilityLabel("Remove “\(question.title)”")
                case .preset(let id):
                    Button { togglePreset(id) } label: {
                        label(question, answer: answer, verdict: verdict, trailsButton: false)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(question.isOn ? "Stop asking “\(question.title)” as you type" : "Ask “\(question.title)” as you type")
                    .accessibilityLabel(question.title)
                    .accessibilityValue(value(of: question))
                    .accessibilityAddTraits(question.isOn ? .isSelected : [])
                }
            }
            .glassEffect(glass(for: question, verdict: verdict, answer: answer), in: .capsule)
        }
        .onHover { isOver in
            if isOver { hovered = question.id } else if hovered == question.id { hovered = nil }
        }
    }

    /// The question's icon and title, and while it is on, its answer, a spinner while the answer is on its way, or
    /// an ellipsis while there is no text to decide about.
    private func label(_ question: LiveQuestion, answer: Decision?, verdict: Decision.Verdict?, trailsButton: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: question.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(question.isOn ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .frame(width: 14)
            Text(question.title)
                .font(.system(size: 12, weight: question.isOn ? .semibold : .medium))
                .foregroundStyle(question.isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            if question.isOn {
                if let answer, let verdict {
                    Image(systemName: symbol(of: verdict))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint(of: verdict, answer).map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: answer)
                        .padding(.leading, 2)
                    Text(verdict == .unsure ? "Not sure" : answer.chosen.label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(Decision.percent(answer.confidence))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else if live.isPending(question) {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 2)
                } else {
                    Text("…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, trailsButton ? 3 : 13)
        .frame(height: Self.height)
    }

    /// The plus or the cross at a capsule's end: quiet until the pointer is over the capsule.
    private func trailing(_ symbol: String, highlighted: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(highlighted ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: 20, height: Self.height)
            .padding(.trailing, 4)
            .contentShape(.rect)
    }

    /// The capsule's glass: plain while the question is off, the chosen segment's pink while it is on and waiting,
    /// then green for Yes, red for No, the colour of how sure the model is for one of your own answers, and plain
    /// again for Not Sure. Every capsule answers the pointer, since each takes a click.
    private func glass(for question: LiveQuestion, verdict: Decision.Verdict?, answer: Decision?) -> Glass {
        guard question.isOn else { return .regular.interactive() }
        switch verdict {
        case .yes?: return .regular.tint(Color(nsColor: .addedText).opacity(0.3)).interactive()
        case .no?: return .regular.tint(Color(nsColor: .removedText).opacity(0.3)).interactive()
        case .chosen?:
            guard let answer else { return .regular.interactive() }
            return .regular.tint(confidenceColor(answer.confidence).opacity(0.3)).interactive()
        case .unsure?: return .regular.interactive()
        case nil: return .regular.tint(.meralinePink.opacity(0.22)).interactive()
        }
    }

    private func symbol(of verdict: Decision.Verdict) -> String {
        switch verdict {
        case .yes, .chosen: "checkmark"
        case .no: "xmark"
        case .unsure: "questionmark"
        }
    }

    /// Green for Yes and red for No, how sure the model is for one of your own answers, nothing for Not Sure.
    private func tint(of verdict: Decision.Verdict, _ decision: Decision) -> Color? {
        switch verdict {
        case .yes: Color(nsColor: .addedText)
        case .no: Color(nsColor: .removedText)
        case .chosen: confidenceColor(decision.confidence)
        case .unsure: nil
        }
    }

    private func value(of question: LiveQuestion) -> String {
        guard question.isOn else { return "Off" }
        guard let answer = live.answer(for: question) else { return live.isPending(question) ? "Deciding" : "Nothing to decide about yet" }
        return answer.summary(unsureBelow: unsureBelow)
    }
}

/// Three segments in a glass capsule at the games' place in Decision mode, beside the answers: the whole text,
/// each word, or each line (see `DecisionScope`). The chosen one carries the mode toggle's tinted pill, which
/// slides across when the scope changes.
struct DecisionScopeToggle: View {
    let scope: DecisionScope
    let choose: (DecisionScope) -> Void

    @Namespace private var thumb
    @State private var hovered: DecisionScope?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DecisionScope.allCases) { segment($0) }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: scope)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What to decide about")
    }

    private func segment(_ candidate: DecisionScope) -> some View {
        let isOn = scope == candidate
        return Button { choose(candidate) } label: {
            Image(systemName: candidate.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 24)
                .background {
                    if isOn {
                        Color.clear
                            .glassEffect(.regular.tint(.meralinePink.opacity(0.22)).interactive(), in: .capsule)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    } else if hovered == candidate {
                        Capsule().fill(.primary.opacity(0.07))
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = candidate } else if hovered == candidate { hovered = nil }
        }
        .help(candidate.help)
        .accessibilityLabel(candidate.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The decisions about each word or line of a text, in the answer's place (see `DecisionBatch`): a line with the
/// counts, then the words or lines grouped by answer, Yes on green, No on red, your own answers and Not Sure in
/// neutral colors, words as capsules in a row that wraps and lines as a list, each with how sure Jev is, surest
/// first. Every answer starts folded to its header, its count, and a chevron, so a long text reads as a short
/// summary first; a click on the header opens its words or lines in place and folds them back (`openGroups`,
/// which `PanelLayout` keeps by turn, in memory only). While the batches come, the line counts them up.
struct BulkDecisionCard: View {
    let batch: DecisionBatch
    /// Under this confidence an item is Not Sure (see `Preferences.unsureBelow`).
    let unsureBelow: Double
    let isAnswering: Bool
    /// The answers whose words or lines show under their header; the rest show the header alone.
    var openGroups: Set<DecisionBatch.Group.ID> = []
    var toggle: (DecisionBatch.Group.ID) -> Void = { _ in }

    var body: some View {
        let groups = batch.groups(unsureBelow: unsureBelow)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isAnswering, !batch.isComplete {
                    ProgressView().controlSize(.mini)
                }
                Text(headline(of: groups))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                let isOpen = openGroups.contains(group.id)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        toggle(group.id)
                    } label: {
                        header(of: group, isOpen: isOpen).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(isOpen ? "Hide the \(nouns(group.items.count))" : "Show the \(nouns(group.items.count))")
                    .accessibilityLabel("\(group.label), \(group.items.count.formatted()) \(nouns(group.items.count))")
                    .accessibilityValue(isOpen ? "Open" : "Folded")
                    .accessibilityHint(isOpen ? "Folds them away" : "Shows them")
                    if isOpen {
                        if batch.scope == .words {
                            words(of: group)
                        } else {
                            lines(of: group)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(.smooth(duration: 0.2), value: batch.items.count)
        .animation(.smooth(duration: 0.25), value: openGroups)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(batch.summary(unsureBelow: unsureBelow))
    }

    /// "lines", or "line" for one.
    private func nouns(_ count: Int) -> String {
        "\(batch.scope.noun)\(count == 1 ? "" : "s")"
    }

    /// "12 of 45 words decided…", then "45 words · Yes 12 · No 30 · Not sure 3".
    private func headline(of groups: [DecisionBatch.Group]) -> String {
        guard batch.isComplete else { return "\(batch.items.count.formatted()) of \(batch.count) decided…" }
        let counts = groups.map { "\($0.label) \($0.items.count.formatted())" }.joined(separator: " · ")
        return counts.isEmpty ? batch.count : "\(batch.count) · \(counts)"
    }

    /// The answer's symbol, its name and count, and a chevron that turns up while its items show. The whole row
    /// takes the click, as a quote's header does.
    private func header(of group: DecisionBatch.Group, isOpen: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(of: group.verdict))
                .font(.system(size: group.verdict == .chosen ? 7 : 11, weight: .bold))
                .foregroundStyle(tint(of: group.verdict).map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: 14)
            Text("\(group.label) · \(group.items.count.formatted())")
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .accessibilityHidden(true)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func words(of group: DecisionBatch.Group) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(group.items) { item in
                HStack(spacing: 5) {
                    Text(item.text)
                        .font(.system(size: 12, weight: .medium))
                    Text(Decision.percent(item.decision.confidence))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(fill(of: group.verdict), in: .capsule)
                .help(help(for: item))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.text), \(help(for: item))")
            }
        }
    }

    private func lines(of group: DecisionBatch.Group) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(group.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.text)
                        .font(.system(size: 12))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(Decision.percent(item.decision.confidence))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill(of: group.verdict), in: .rect(cornerRadius: 8))
                .help(help(for: item))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.text), \(help(for: item))")
            }
        }
    }

    private func symbol(of verdict: Decision.Verdict) -> String {
        switch verdict {
        case .yes: "checkmark"
        case .no: "xmark"
        case .unsure: "questionmark"
        case .chosen: "circle.fill"
        }
    }

    /// Green for Yes and red for No, as `DecisionCard` has them; nothing for the rest.
    private func tint(of verdict: Decision.Verdict) -> Color? {
        switch verdict {
        case .yes: Color(nsColor: .addedText)
        case .no: Color(nsColor: .removedText)
        case .unsure, .chosen: nil
        }
    }

    private func fill(of verdict: Decision.Verdict) -> AnyShapeStyle {
        tint(of: verdict).map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(.primary.opacity(0.05))
    }

    private func help(for item: DecisionBatch.Item) -> String {
        let sure = "\(Decision.percent(item.decision.confidence)) confident"
        return item.decision.isUnsure(below: unsureBelow) ? "Not sure, leaning \(item.decision.chosen.label), \(sure)" : "\(item.decision.chosen.label), \(sure)"
    }
}
