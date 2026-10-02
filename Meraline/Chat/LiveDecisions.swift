import Foundation
import Observation

/// A question kept from the input with the plus on its capsule (see `ChatSession.keepLiveQuestion()`): asked
/// beside the presets while it is on, until its cross removes it or the chat ends. In memory only, like a draft;
/// a question for keeps is a preset, in Settings › Prompt.
nonisolated struct KeptQuestion: Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    var isOn: Bool
}

/// A question the Context card decides live (see `LiveDecisions`): one kept from the input, the one in the input,
/// or one of Decision's presets, which a click on its capsule turns on or off. Each is a question less the answers
/// it names, and those answers (see `DecisionAnswers.split`), with the title and icon its capsule wears.
nonisolated struct LiveQuestion: Equatable, Hashable, Sendable, Identifiable {
    enum Source: Equatable, Hashable, Sendable {
        /// The question typed in the input, asked whenever there is one.
        case input
        /// A question kept from the input, by its id, asked while it is on (see `KeptQuestion`).
        case kept(UUID)
        /// A preset of Decision mode, by its id, asked while it is on (see `LiveDecisions.enabledPresets`).
        case preset(PromptPreset.ID)
    }

    let source: Source
    let title: String
    let symbol: String
    let question: String
    let answers: DecisionAnswers
    /// Whether the question is asked: the input's always, a kept question's or a preset's while it is on.
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

    /// What the capsule asks, for `DecisionClient.decide(_:about:settings:provider:)`.
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

    /// A preset's question, or nil for one with no text; its capsule wears the preset's title and icon.
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

/// The decisions the Context card makes as you type, in Decision mode, while its Live switch is on (`isOn`, off
/// in every new chat): the questions kept from the input, the question in the input, and the presets turned on
/// (`LiveQuestion`) go to the decision provider in use in one request about the chat's texts and the card's
/// (`DecisionClient.decide(_:about:settings:provider:)`), and each answer shows on its capsule under the text,
/// without a turn in the chat; Return still asks for a decision there. They go after each pause in typing
/// (`debounce`), and at the latest `maxWait` after typing began, so a sentence typed without a pause is still
/// decided about as it grows. One request is in flight at a time and the latest change waits behind it: a reply
/// that comes back about an earlier text still shows, dimmed, until the next one lands, so a capsule never goes
/// blank while you type. An answer is kept while its text and question stay the same, whichever capsule asks it,
/// so turning a preset on asks only that preset, turning it off and on again asks nothing, and a question kept
/// from the input takes the input's answer with it. The switch, the presets turned on, and the kept questions are
/// the chat's: a new chat starts with the switch off and nothing on (`reset()`), and so does the switch itself
/// when it is turned, the input's question aside, which is asked as it is. All of it lives in memory; the ledger
/// counts the decisions and what they took.
@MainActor
@Observable
final class LiveDecisions {
    /// How long typing pauses before the questions go, so a word typed out costs one request, not one a letter.
    static let debounce: TimeInterval = 0.4
    /// How long typing may go on before the questions go anyway, so the capsules keep up with a long sentence.
    static let maxWait: TimeInterval = 1.0

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

    /// Whether the card decides as you type: its Live switch, off in every new chat.
    var isOn = false
    /// The presets asked beside the input's question, by id, while they are on (see `togglePreset(_:)`).
    var enabledPresets: Set<PromptPreset.ID> = []
    /// The questions kept from the input, in the order they were kept (see `keep(_:)`).
    private(set) var keptQuestions: [KeptQuestion] = []
    /// The questions the card shows: those kept from the input, the input's, then every preset, on or off.
    private(set) var questions: [LiveQuestion] = []
    /// The latest answer to each question, by its id, about the texts it was asked about.
    private(set) var answers: [LiveQuestion.ID: Answer] = [:]
    /// The questions whose answer about the current texts hasn't come: never answered, or answered about an
    /// earlier text, which shows dimmed meanwhile (see `isStale(_:)`).
    private(set) var pending: Set<LiveQuestion.ID> = []
    /// Why the last ask brought no answer, in the provider's words, until the next change.
    private(set) var failure: String?
    /// The pause and the longest typing goes before an ask; `debounce` and `maxWait` outside tests.
    @ObservationIgnored var debounce = LiveDecisions.debounce
    @ObservationIgnored var maxWait = LiveDecisions.maxWait
    /// Waits out the pause, then queues the ask for the worker.
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// When the typing the timer waits on began, for `maxWait`.
    @ObservationIgnored private var typingBegan: Date?
    /// Sends the queued ask, one request at a time, and the one queued meanwhile after it.
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerGeneration = 0
    @ObservationIgnored private var queued: Ask?
    @ObservationIgnored private var lastAsk: Ask?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let usage: UsageLedger
    @ObservationIgnored private let decide: Decide

    init(preferences: Preferences, usage: UsageLedger, decide: @escaping Decide = DecisionClient.decide) {
        self.preferences = preferences
        self.usage = usage
        self.decide = decide
    }

    /// The answer to a question, while it is on: the latest, about the current texts or, dimmed, an earlier one.
    func answer(for question: LiveQuestion) -> Decision? {
        question.isOn ? answers[question.id]?.decision : nil
    }

    /// Whether a newer answer is on its way.
    func isPending(_ question: LiveQuestion) -> Bool {
        pending.contains(question.id)
    }

    /// Whether the answer shown is about an earlier text, with a newer one on its way.
    func isStale(_ question: LiveQuestion) -> Bool {
        isPending(question) && answers[question.id] != nil
    }

    /// Whether nothing is asked: no question in the input, none kept, and no preset on.
    var asksNothing: Bool { !questions.contains(where: \.isOn) }

    // MARK: The switch, the presets, and the kept questions

    /// The Live switch: on or off, starting over with no preset on and no kept question; the input's question is
    /// asked as it is.
    func toggle() {
        isOn.toggle()
        enabledPresets = []
        keptQuestions = []
    }

    func togglePreset(_ id: PromptPreset.ID) {
        if enabledPresets.remove(id) == nil { enabledPresets.insert(id) }
    }

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

    /// A new chat: the switch off, no preset on, no kept question, and nothing shown or on its way.
    func reset() {
        isOn = false
        enabledPresets = []
        keptQuestions = []
        update(nil)
    }

    // MARK: Asking

    /// What the card asks now, or nil to show nothing (the switch off, another mode, the card closed). Called on
    /// every change of the text or the questions: the ask goes after a pause of `debounce`, at the latest
    /// `maxWait` after the typing began, or with `atOnce` right away, as a click on a capsule does. The same ask
    /// again changes nothing.
    func update(_ ask: Ask?, atOnce: Bool = false) {
        guard let ask else {
            guard lastAsk != nil || !questions.isEmpty else { return }
            lastAsk = nil
            stop()
            questions = []
            answers = [:]
            pending = []
            failure = nil
            return
        }
        // The same ask again changes nothing, unless a click asks for it at once while typing's pause runs.
        if let lastAsk, lastAsk == ask, !(atOnce && timer != nil) { return }
        lastAsk = ask
        questions = ask.questions
        // The answers to questions still shown stay, whatever text they were about, so a capsule keeps showing
        // its last answer, dimmed, until the next comes; a question asked under another name, as one kept from the
        // input is, takes the answer about the current texts.
        // Every answer so far by what it was about, the input's included, before the questions no longer shown go.
        let known = Dictionary(answers.values.map { ($0.about, $0.decision) }, uniquingKeysWith: { first, _ in first })
        answers = answers.filter { id, _ in ask.questions.contains { $0.id == id } }
        for question in ask.questions {
            let about = About(ask.state, question)
            if answers[question.id]?.about != about, let decision = known[about] {
                answers[question.id] = Answer(decision: decision, about: about)
            }
        }
        failure = nil
        guard !ask.state.isEmpty, !ask.state.allSatisfy({ $0.text.trimmed.isEmpty }) else {
            // Nothing to decide about: nothing waits, and no answer about an earlier text stays.
            answers = [:]
            pending = []
            cancelTimer()
            return
        }
        pending = Set(outdated(in: ask).map(\.id))
        guard !pending.isEmpty else {
            cancelTimer()
            return
        }
        schedule(ask, atOnce: atOnce)
    }

    /// The questions on with no answer about `ask`'s texts yet.
    private func outdated(in ask: Ask) -> [LiveQuestion] {
        ask.questions.filter { $0.isOn && answers[$0.id]?.about != About(ask.state, $0) }
    }

    /// Waits out the pause, then queues the ask: `debounce` after the last change, or what is left of `maxWait`
    /// since the typing began, whichever is sooner.
    private func schedule(_ ask: Ask, atOnce: Bool) {
        timer?.cancel()
        let now = Date.now
        let began = typingBegan ?? now
        typingBegan = began
        let delay = atOnce ? 0 : min(debounce, max(0, maxWait - now.timeIntervalSince(began)))
        timer = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            timer = nil
            typingBegan = nil
            queued = ask
            runWorker()
        }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
        typingBegan = nil
        queued = nil
    }

    private func stop() {
        cancelTimer()
        worker?.cancel()
        worker = nil
    }

    /// Sends the queued ask, and whatever is queued by the time it is answered, one request at a time.
    private func runWorker() {
        guard worker == nil else { return }
        workerGeneration += 1
        let generation = workerGeneration
        worker = Task { [weak self] in
            while let ask = self?.queued {
                self?.queued = nil
                await self?.send(ask)
            }
            if let self, workerGeneration == generation { worker = nil }
        }
    }

    /// One request for the questions on that have no answer about `ask`'s texts, a question asked twice over, as a
    /// preset's is when it is in the input too, going once. The answers go to the capsules still shown, even when
    /// the text has moved on meanwhile, which shows them dimmed until the next request's come.
    private func send(_ ask: Ask) async {
        let targets = outdated(in: ask)
        guard !targets.isEmpty else { return }
        var seen: Set<About> = []
        let distinct = targets.filter { seen.insert(About(ask.state, $0)).inserted }
        do {
            let reply = try await decide(distinct.map(\.decisionQuestion), ask.state, ask.settings, ask.provider)
            guard !Task.isCancelled else { return }
            for question in targets where questions.contains(where: { $0.id == question.id }) {
                let about = About(ask.state, question)
                guard let twin = distinct.first(where: { About(ask.state, $0) == about }),
                      let decision = reply.decisions[twin.id] else { continue }
                answers[question.id] = Answer(decision: decision, about: about)
            }
            if let lastAsk { pending = Set(outdated(in: lastAsk).map(\.id)) }
            count(reply, asked: distinct, about: ask.state, provider: ask.provider, settings: ask.settings)
            Log.chat.info("Live decisions: \(ask.provider.name) answered \(reply.decisions.count) question(s)")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
            // Nothing waits any more; the next change tries again.
            pending = []
            Log.chat.error("Live decisions failed: \(error.localizedDescription)")
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
