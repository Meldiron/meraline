import AppKit
import SwiftUI

/// What Jev decided, in the answer's place (see `Decision`): a glass disc with a check on green glass for Yes, a
/// cross on red for No, a question mark on neutral glass for Not Sure, or a check on neutral glass for one of your
/// own answers, which get no color; a ring around the disc is how sure Jev is, and beside it the answer and
/// “82% confident”. Under them, every answer with its probability, the chosen one in the primary color. The check,
/// the cross, and the words carry the meaning, so the colors are only a help, as in Show What Changed.
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
            ProbabilityRow(decision: decision)
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

    /// Green for Yes and red for No, deeper shades on light glass (see `NSColor.addedText`); nothing for the rest.
    private var tint: Color? {
        switch verdict {
        case .yes: Color(nsColor: .addedText)
        case .no: Color(nsColor: .removedText)
        case .unsure, .chosen: nil
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
        .frame(maxWidth: 260)
        .fixedSize(horizontal: true, vertical: false)
        .glassEffect(.regular, in: .capsule)
        .help(answers.isOrdered
            ? "The levels Jev places the text along. Name your own after the question, from lowest to highest with < between them"
            : "The answers Jev picks from. Name your own after the question, with / between them, or < for levels in order")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answers: \(answers.text)")
    }
}

/// Under the mode row while a decision has no text to decide about: what to add, and a button that opens a card to
/// write it in (see `TypedStateCard`). Glass like the setup row, with the faint pink of the panel's buttons.
struct DecisionStateRow: View {
    let write: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.quote")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("What should Jev decide about?")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add the text you selected or copied with the buttons above the window, or write it here. A decision needs text; pictures and files don’t count.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Write It", action: write)
                .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Text written in the window itself for a decision, between the input and the row under it, like a selected
/// text's card: a header that counts its words, a field of a few lines that grows with the text, and a cross.
/// It goes with the question as a text of its own, quoted in the conversation like a selection.
struct TypedStateCard: View {
    @Binding var text: String
    let remove: () -> Void

    @FocusState private var isFocused: Bool
    @State private var textHeight: CGFloat = 0

    private static let font = Font.system(size: 13)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Written here")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("· \(words) \(words == 1 ? "word" : "words")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                CardButton(symbol: "xmark", label: "Leave out the written text", action: remove)
                    .help("Leave it out")
            }
            .lineLimit(1)
            ZStack(alignment: .topLeading) {
                // The text laid out the way the editor lays it out, never drawn, so the editor fits it.
                Text(text.isEmpty ? " " : text)
                    .font(Self.font)
                    .lineSpacing(2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }
                if text.isEmpty {
                    Text("Paste or type the text to decide about…")
                        .font(Self.font)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Self.font)
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .tint(.meralinePink)
                    .focused($isFocused)
                    .frame(height: min(max(textHeight, 36), 160))
            }
            .padding(.horizontal, 4)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 10))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Text written for the decision")
    }

    private var words: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
