import Foundation

/// The answers a decision picks from (see `DecisionRequest`): Yes and No, unless the question names its own after
/// its last question mark or colon, separated by slashes, or by less-than signs for answers in order, as in
/// “Which team should handle this? Billing / Technical / Sales” or “How urgent is this? Low < Medium < High”.
/// Settings › Prompt › Decisions sets the answers a question that names none picks from, written the same way.
nonisolated struct DecisionAnswers: Equatable, Hashable, Sendable {
    /// The answers as typed, in order.
    let options: [String]
    /// The answers are levels of one thing, first to last, and Jev places the text along them (its `score`
    /// question) rather than picking one of a set (its `choice`).
    let isOrdered: Bool

    static let yesNo = DecisionAnswers(options: ["Yes", "No"], isOrdered: false)
    /// The answers Settings starts with.
    static let defaultText = "Yes / No"
    /// The most answers Jev takes: 255 in a set, and 10 levels in order; more levels go as a set.
    static let optionLimit = 255
    static let levelLimit = 10
    /// The longest an answer may be, so a slash in a sentence never splits it into answers.
    static let optionLength = 40

    init(options: [String], isOrdered: Bool) {
        self.options = options
        self.isOrdered = isOrdered
    }

    /// What Jev is asked: its yes/no question for Yes and No, in either order and any case; a set to pick from; or
    /// levels in order, when there are few enough.
    enum Kind: Equatable, Sendable {
        case yesNo
        case choice
        case score
    }

    var isYesNo: Bool {
        Set(options.map { $0.lowercased() }) == ["yes", "no"]
    }

    var kind: Kind {
        if isYesNo { return .yesNo }
        return isOrdered && options.count <= Self.levelLimit ? .score : .choice
    }

    /// The answers written as Settings writes them: “Yes / No”, or “Low < Medium < High” in order.
    var text: String {
        options.joined(separator: isOrdered ? " < " : " / ")
    }

    /// The answers written as `text` writes them: two or more, none empty, longer than `optionLength`, or on more
    /// than one line, no two alike, and at most `optionLimit`. Nil for anything else.
    static func parse(_ text: String) -> DecisionAnswers? {
        let isOrdered = text.contains("<")
        let separator: Character = isOrdered ? "<" : "/"
        guard text.contains(separator) else { return nil }
        let parts = text.split(separator: separator, omittingEmptySubsequences: false).map { $0.trimmed }
        guard parts.count >= 2, parts.count <= optionLimit,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= optionLength && !$0.contains(where: \.isNewline) }),
              Set(parts.map { $0.lowercased() }).count == parts.count else { return nil }
        return DecisionAnswers(options: parts, isOrdered: isOrdered)
    }

    /// A question and its answers: those it names after its last question mark or colon, or `fallback` when it
    /// names none, in which case the question goes whole.
    static func split(_ question: String, fallback: DecisionAnswers) -> (question: String, answers: DecisionAnswers) {
        let question = question.trimmed
        guard let mark = question.lastIndex(where: { $0 == "?" || $0 == ":" }),
              let answers = parse(String(question[question.index(after: mark)...])) else { return (question, fallback) }
        return (String(question[...mark]).trimmed, answers)
    }
}

/// What Jev decided (see `DecisionClient`): every answer with the probability Jev gives it, and how sure Jev is,
/// from 0 to 1: Jev's own `confidence`, how far the probability gathers on one answer over an even spread, which
/// for two answers is twice the winner's probability less one. The answer is the most probable one; under
/// `Preferences.unsureBelow` it shows as Not Sure, with the answer it leans to.
nonisolated struct Decision: Equatable, Sendable {
    struct Option: Equatable, Sendable, Identifiable {
        let label: String
        let probability: Double

        var id: String { label }
    }

    /// The answers in their order, with Jev's probability for each.
    let options: [Option]
    let isOrdered: Bool
    /// For answers in order, where Jev placed the text along them: 0 at the first, one less than their count at
    /// the last, and between two when it isn't sure.
    let score: Double?
    let isYesNo: Bool
    let confidence: Double

    /// The confidence Settings starts with: under it, Not Sure. For Yes and No, that is a winner under 75%.
    static let defaultUnsureBelow = 0.5

    init(options: [Option], isOrdered: Bool = false, score: Double? = nil, isYesNo: Bool = false, confidence: Double) {
        self.options = options
        self.isOrdered = isOrdered
        self.score = score
        self.isYesNo = isYesNo
        self.confidence = min(max(confidence, 0), 1)
    }

    /// The most probable answer, the first among equals.
    var chosen: Option {
        options.dropFirst().reduce(options.first ?? Option(label: "", probability: 0)) { best, option in
            option.probability > best.probability ? option : best
        }
    }

    /// How the answer shows: Yes or No, on green or red; Not Sure; or one of your own answers, in neutral colors.
    enum Verdict: Equatable, Sendable {
        case yes
        case no
        case unsure
        case chosen
    }

    func isUnsure(below threshold: Double) -> Bool {
        confidence < threshold
    }

    func verdict(unsureBelow threshold: Double) -> Verdict {
        if isUnsure(below: threshold) { return .unsure }
        guard isYesNo else { return .chosen }
        return chosen.label.lowercased() == "yes" ? .yes : .no
    }

    /// The decision in words, for the transcript, Copy Answer, and Insert Answer: “Yes (82% confident)”,
    /// “Technical (78% confident)”, or “Not sure, leaning Yes (30% confident)”.
    func summary(unsureBelow threshold: Double) -> String {
        let sure = "\(Self.percent(confidence)) confident"
        return isUnsure(below: threshold) ? "Not sure, leaning \(chosen.label) (\(sure))" : "\(chosen.label) (\(sure))"
    }

    /// A share written as a whole percentage: “82%”.
    static func percent(_ share: Double) -> String {
        "\(Int((min(max(share, 0), 1) * 100).rounded()))%"
    }

    /// Jev's confidence worked out from a distribution, for a reply that carries none: how far the largest
    /// probability stands above an even spread, from 0 for even to 1 for certain.
    static func confidence(over probabilities: [Double]) -> Double {
        guard probabilities.count > 1, let peak = probabilities.max() else { return 0 }
        let count = Double(probabilities.count)
        return min(max((count * peak - 1) / (count - 1), 0), 1)
    }
}
