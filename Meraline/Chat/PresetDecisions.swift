import Foundation

/// What Jev decided about each of Decision's presets, asked at once by the circle at the end of their row (see
/// `PromptPresets`, `ChatSession.askPresets(_:)`): every preset with a question, in the row's order, each its
/// title, its question less the answers it names, those answers (see `DecisionAnswers.split`), and its decision
/// once it comes. One request carries every question, named by its preset, as the live decisions' are
/// (`DecisionRequest.body(model:state:questions:)`), or as many as the provider takes
/// (`Provider.questionsPerRequest`), and the round so far comes back after each reply, so the card fills as they
/// come (`StreamOutput.presetDecisions`, `Turn.presetDecisions`); the turn's `answer` then sums it up (`summary`).
nonisolated struct PresetDecisions: Equatable, Sendable {
    struct Question: Equatable, Sendable, Identifiable {
        /// The preset's id, which names the question in the request and in the reply.
        let id: PromptPreset.ID
        /// The preset's title, or its question for a preset without one, for the card and the summary.
        let title: String
        let question: String
        let answers: DecisionAnswers
        var decision: Decision?

        /// The question as the request names it.
        var decisionQuestion: DecisionQuestion { DecisionQuestion(id: id, question: question, answers: answers) }
    }

    var questions: [Question]

    /// The presets with a question, in their order, each with the answers it names or `fallback` when it names
    /// none; none decided yet.
    init(presets: [PromptPreset], fallback: DecisionAnswers) {
        questions = presets.compactMap { preset in
            let split = DecisionAnswers.split(preset.text, fallback: fallback)
            guard !split.question.isEmpty else { return nil }
            let title = preset.title.trimmed
            return Question(id: preset.id, title: title.isEmpty ? split.question : title, question: split.question, answers: split.answers)
        }
    }

    var isEmpty: Bool { questions.isEmpty }

    var isComplete: Bool { questions.allSatisfy { $0.decision != nil } }

    /// The decisions that came, for the usage ledger.
    var decided: [Decision] { questions.compactMap(\.decision) }

    /// The questions with no decision yet, as the request names them.
    var undecided: [DecisionQuestion] { questions.filter { $0.decision == nil }.map(\.decisionQuestion) }

    /// The round with every question open again, for Ask Again and Try Again.
    var cleared: PresetDecisions {
        var round = self
        for index in round.questions.indices { round.questions[index].decision = nil }
        return round
    }

    /// The titles in a line, as the turn's question: “Urgent? · Scam? · Tone · Priority”.
    var headline: String { questions.map(\.title).joined(separator: " · ") }

    /// The decisions in words, one a line, for the transcript, Copy Answer, and Insert Answer:
    /// “- Urgent?: Yes (82% confident)”, and “not decided” for a question whose answer never came.
    func summary(unsureBelow threshold: Double) -> String {
        questions.map { "- \($0.title): \($0.decision?.summary(unsureBelow: threshold) ?? "not decided")" }.joined(separator: "\n")
    }

    /// Takes in the answers a reply brought, by the question's id.
    mutating func take(_ decisions: [DecisionQuestion.ID: Decision]) {
        for index in questions.indices {
            if let decision = decisions[questions[index].id] { questions[index].decision = decision }
        }
    }
}
