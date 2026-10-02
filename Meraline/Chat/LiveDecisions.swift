import Foundation
import Observation

/// A question kept from the input with the plus on its capsule (see `ChatSession.keepLiveQuestion()`): asked
/// beside the presets while it is on, until its cross removes it, every chat is forgotten, or Meraline quits. In
/// memory only, like a draft; a question for keeps is a preset, in Settings › Prompt.
nonisolated struct KeptQuestion: Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    var isOn: Bool
}

/// A question the Context card decides live (see `LiveDecisions`): the one in the input, one kept from it, or
/// one of Decision's presets, which a click on its capsule turns on or off. Each is a question less the answers it
/// names, and those answers (see `DecisionAnswers.split`), with the title and icon its capsule wears.
nonisolated struct LiveQuestion: Equatable, Hashable, Sendable, Identifiable {
    enum Source: Equatable, Hashable, Sendable {
        /// The question typed in the input, asked whenever there is one.
        case input
        /// A question kept from the input, by its id, asked while it is on (see `KeptQuestion`).
        case kept(UUID)
        /// A preset of Decision mode, by its id, asked while it is on (see `Preferences.livePresets`).
        case preset(PromptPreset.ID)
    }

    let source: Source
    let title: String
    let symbol: String
    let question: String
    let answers: DecisionAnswers
    /// Whether the question is asked: the input's always, a preset's while it is on.
    let isOn: Bool

    /// The question's name in the request and the reply.
    var id: String {
        switch source {
        case .input: "input"
        case .kept(let id): "kept.\(id.uuidString)"
        case .preset(let id): "preset.\(id)"
        }
    }

    var presetID: PromptPreset.ID? {
        if case .preset(let id) = source { id } else { nil }
    }

    var keptID: UUID? {
        if case .kept(let id) = source { id } else { nil }
    }

    /// What the chip asks, for `DecisionClient.decide(_:about:settings:provider:)`.
    var decisionQuestion: DecisionQuestion { DecisionQuestion(id: id, question: question, answers: answers) }

    /// The input's question, or nil while nothing is typed; `fallback` is what a question that names no answers
    /// picks from (see `ChatSession.defaultAnswers`).
    static func input(_ draft: String, fallback: DecisionAnswers) -> LiveQuestion? {
        let split = DecisionAnswers.split(draft, fallback: fallback)
        guard !split.question.isEmpty else { return nil }
        return LiveQuestion(source: .input, title: split.question, symbol: "text.cursor", question: split.question, answers: split.answers, isOn: true)
    }

    /// A kept question, or nil for one that names only answers.
    static func kept(_ kept: KeptQuestion, fallback: DecisionAnswers) -> LiveQuestion? {
        let split = DecisionAnswers.split(kept.text, fallback: fallback)
        guard !split.question.isEmpty else { return nil }
        return LiveQuestion(source: .kept(kept.id), title: split.question, symbol: "text.bubble", question: split.question, answers: split.answers, isOn: kept.isOn)
    }

    /// A preset's question, or nil for one with no text; its chip wears the preset's title and icon.
    static func preset(_ preset: PromptPreset, isOn: Bool, fallback: DecisionAnswers) -> LiveQuestion? {
        let split = DecisionAnswers.split(preset.text, fallback: fallback)
        guard !split.question.isEmpty else { return nil }
        let title = preset.title.trimmed
        return LiveQuestion(
            source: .preset(preset.id), title: title.isEmpty ? split.question : title, symbol: preset.shownSymbol,
            question: split.question, answers: split.answers, isOn: isOn
        )
    }
}

/// The decisions the Context card makes as you type, in Decision mode, once its Live switch is on (see
/// `Preferences.liveDecisions`): after each pause in typing (`debounce`), the question in the input and the
/// presets turned on (`LiveQuestion`) go to the decision provider in use in one request about the chat's texts and
/// the card's (`DecisionClient.decide(_:about:settings:provider:)`), and each answer shows on its capsule under
/// the text, without a turn in the chat; Return still asks for a decision there. The plus on the input's capsule
/// keeps its question as one of its own (`keptQuestions`), so several of yours are asked beside the presets. One
/// ask is in flight at a time: a change before the reply comes drops it, so a capsule never jumps back to an older
/// text's answer. An answer is kept while its text and question stay the same, whichever capsule asks it, so
/// turning a preset on asks only that preset, turning it off and on again asks nothing, and a question kept from
/// the input takes the input's answer with it. All of it lives in memory; the ledger counts the decisions and
/// what they took.
@MainActor
@Observable
final class LiveDecisions {
    /// How long typing pauses before the questions go, so a word typed out costs one request, not one a letter.
    static let debounce: Duration = .milliseconds(400)

    /// What the card asks now: the texts, the questions, and which provider answers.
    struct Ask {
        var state: [SelectedText]
        var questions: [LiveQuestion]
        var provider: Provider
        var settings: ProviderSettings
    }

    /// What a question is about: its texts and its wording, which an answer is good for as long as they stay.
    struct About: Hashable {
        let texts: [String]
        let question: String
        let answers: DecisionAnswers

        init(_ state: [SelectedText], _ question: LiveQuestion) {
            texts = state.map(\.text)
            self.question = question.question
            answers = question.answers
        }
    }

    struct Answer: Equatable {
        let decision: Decision
        let about: About
    }

    typealias Decide = @MainActor ([DecisionQuestion], [SelectedText], ProviderSettings, Provider) async throws -> DecisionClient.LiveReply

    /// The questions the card shows, the input's first, then those kept from it, then every preset, on or off.
    private(set) var questions: [LiveQuestion] = []
    /// The questions kept from the input, in the order they were kept (see `keep(_:)`).
    private(set) var keptQuestions: [KeptQuestion] = []
    /// The latest answer to each question, by its id, about the current texts.
    private(set) var answers: [LiveQuestion.ID: Answer] = [:]
    /// The questions waiting for an answer, in the debounce or on their way.
    private(set) var pending: Set<LiveQuestion.ID> = []
    /// Why the last ask brought no answer, in the provider's words, until the next ask.
    private(set) var failure: String?
    /// How long typing pauses before the questions go; `debounce` outside tests.
    @ObservationIgnored var debounce = LiveDecisions.debounce
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Whether the task is still waiting out the pause, which a click then skips.
    @ObservationIgnored private var isDelaying = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastAsk: Ask?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let usage: UsageLedger
    @ObservationIgnored private let decide: Decide

    init(preferences: Preferences, usage: UsageLedger, decide: @escaping Decide = DecisionClient.decide) {
        self.preferences = preferences
        self.usage = usage
        self.decide = decide
    }

    /// Whether the card has a switch to show: Decision mode with a provider ready, whatever the switch says.
    var isOn: Bool { preferences.liveDecisions }

    /// The answer to a question, while it is on and about the current texts.
    func answer(for question: LiveQuestion) -> Decision? {
        question.isOn ? answers[question.id]?.decision : nil
    }

    func isPending(_ question: LiveQuestion) -> Bool {
        pending.contains(question.id)
    }

    /// Whether nothing is asked: no question in the input and no preset on, for the line that says what to do.
    var asksNothing: Bool { !questions.contains(where: \.isOn) }

    // MARK: Kept questions

    /// Keeps `text` as a question of its own, on, or turns the one with that text on again.
    func keep(_ text: String) {
        let text = text.trimmed
        guard !text.isEmpty else { return }
        if let index = keptQuestions.firstIndex(where: { $0.text == text }) {
            keptQuestions[index].isOn = true
            return
        }
        keptQuestions.append(KeptQuestion(id: UUID(), text: text, isOn: true))
        Log.chat.info("Live decisions keep a question, \(keptQuestions.count) kept")
    }

    func toggleKept(_ id: UUID) {
        guard let index = keptQuestions.firstIndex(where: { $0.id == id }) else { return }
        keptQuestions[index].isOn.toggle()
    }

    func removeKept(_ id: UUID) {
        keptQuestions.removeAll { $0.id == id }
    }

    /// Forgets every kept question, as forgetting every chat does.
    func forgetKeptQuestions() {
        keptQuestions = []
    }

    /// What the card asks now, or nil to show nothing (the switch off, another mode, the card closed). Called on
    /// every change of the text or the question, so a pause of `debounce` after the last one sends the ask, with
    /// `atOnce` right away, as a click on a chip or the switch does. The same ask again changes nothing.
    func update(_ ask: Ask?, atOnce: Bool = false) {
        guard let ask else {
            guard lastAsk != nil || !questions.isEmpty else { return }
            lastAsk = nil
            task?.cancel()
            task = nil
            isDelaying = false
            questions = []
            answers = [:]
            pending = []
            failure = nil
            return
        }
        // The same ask again changes nothing, unless a click asks for it at once while typing's pause runs.
        if let lastAsk, lastAsk == ask, !(atOnce && isDelaying) { return }
        lastAsk = ask
        task?.cancel()
        task = nil
        isDelaying = false
        generation += 1
        questions = ask.questions
        // The answers still about these texts and these questions stay, a preset's while it is off too, so turning
        // it on again asks nothing, and a question asked under another name, as one kept from the input is, takes
        // that answer; the rest go with what changed.
        let known = Dictionary(answers.values.map { ($0.about, $0.decision) }, uniquingKeysWith: { first, _ in first })
        answers = answers.filter { id, answer in
            ask.questions.contains { $0.id == id && answer.about == About(ask.state, $0) }
        }
        for question in ask.questions where answers[question.id] == nil {
            let about = About(ask.state, question)
            if let decision = known[about] { answers[question.id] = Answer(decision: decision, about: about) }
        }
        failure = nil
        let unanswered = ask.questions.filter { $0.isOn && answers[$0.id] == nil }
        guard !unanswered.isEmpty, !ask.state.isEmpty, !ask.state.allSatisfy({ $0.text.trimmed.isEmpty }) else {
            pending = []
            return
        }
        pending = Set(unanswered.map(\.id))
        // A question asked twice, as a preset's is when it is in the input too, goes once.
        var seen: Set<About> = []
        let distinct = unanswered.filter { seen.insert(About(ask.state, $0)).inserted }
        let generation = generation
        let delay = atOnce ? Duration.zero : debounce
        isDelaying = delay > .zero
        task = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            isDelaying = false
            do {
                let reply = try await decide(distinct.map(\.decisionQuestion), ask.state, ask.settings, ask.provider)
                guard !Task.isCancelled, self.generation == generation else { return }
                for question in unanswered {
                    let about = About(ask.state, question)
                    guard let twin = distinct.first(where: { About(ask.state, $0) == about }),
                          let decision = reply.decisions[twin.id] else { continue }
                    answers[question.id] = Answer(decision: decision, about: about)
                }
                pending = []
                count(reply, asked: distinct, about: ask.state, provider: ask.provider, settings: ask.settings)
                Log.chat.info("Live decisions: \(ask.provider.name) answered \(reply.decisions.count) question(s)")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                pending = []
                failure = error.localizedDescription
                Log.chat.error("Live decisions failed: \(error.localizedDescription)")
            }
        }
    }

    /// Counts what a reply brought and took, as a chat's decision counts: the decisions, those under the Not
    /// Sure line, and the model's tokens and cost, estimated from the texts when the provider reports none.
    private func count(_ reply: DecisionClient.LiveReply, asked: [LiveQuestion], about state: [SelectedText], provider: Provider, settings: ProviderSettings) {
        let decided = Array(reply.decisions.values)
        guard !decided.isEmpty else { return }
        let unsure = decided.filter { $0.isUnsure(below: preferences.unsureBelow) }.count
        let model = reply.usage.model ?? DecisionClient.model(of: settings, provider: provider)
        let key = UsageTally.ModelTally.key(provider: provider, model: model)
        let price = usage.price(for: provider, model: model)
        let reported = reply.usage.hasTokens
        var took = reply.usage
        if !reported {
            took.input = UsageTally.estimatedTokens(in: (state.map(\.text) + asked.map(\.question)).joined(separator: "\n"))
            took.output = UsageTally.estimatedTokens(in: decided.map { $0.summary(unsureBelow: 0) }.joined(separator: "\n"))
        }
        usage.record { tally in
            tally.decisions += decided.count
            tally.unsureDecisions += unsure
            tally.liveDecisions += decided.count
            tally.count(answer: took, reported: reported, for: key, price: price)
        }
    }
}

extension LiveDecisions.Ask: Equatable {
    /// The texts compare by what they say and where they came from, since the card's text is read into a
    /// `SelectedText` of its own each time it is looked at.
    static func == (a: Self, b: Self) -> Bool {
        a.state.map(\.text) == b.state.map(\.text) && a.state.map(\.appName) == b.state.map(\.appName)
            && a.questions == b.questions && a.provider == b.provider && a.settings == b.settings
    }
}
