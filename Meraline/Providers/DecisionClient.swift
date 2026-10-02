import Foundation

/// One of several questions asked about the same texts in one request (see `DecisionClient.decide(_:about:settings:provider:)`),
/// named by `id` in the request and in the reply: the live decisions on the Context card ask the question in the
/// input and the presets turned on at once (see `LiveDecisions`).
nonisolated struct DecisionQuestion: Equatable, Hashable, Sendable, Identifiable {
    let id: String
    /// The question less the answers it named, and those answers (see `DecisionAnswers.split`).
    let question: String
    let answers: DecisionAnswers
}

/// A question for a System One model, TypeSafe's Jev or another (see `DecisionClient`): the texts it is about,
/// which go as the request's state,
/// the question, less the answers it named, and the answers it picks from (see `DecisionAnswers`). About each
/// word or line (see `DecisionScope`), the items go in the state too, and each gets a question of its own.
nonisolated struct DecisionRequest: Equatable, Sendable {
    let state: [SelectedText]
    let question: String
    let answers: DecisionAnswers
    /// Each word or line the question is about, in order, or none for the whole text.
    var scope = DecisionScope.whole
    var items: [String] = []

    /// The one question's name in the request and in the reply, about the whole text.
    static let questionID = "decision"

    /// A word's or line's question, by its place among the items.
    static func itemID(_ index: Int) -> String { "item_\(index)" }

    /// The most characters the texts may have to go in a trimmed request beside its batch's items (see
    /// `body(model:itemsFrom:count:trimmed:)`), so a word is read in its sentence when the text is short, and
    /// left to the item and the question when it isn't.
    static let trimmedTextLimit = 2_000

    /// Jev's state: the text with the app it came from, or the texts in order, and the words or lines when the
    /// question is about each.
    var stateJSON: [String: Any] {
        var json = textsJSON
        if !items.isEmpty { json["items"] = items }
        return json
    }

    /// The text with the app it came from, or the texts in order.
    private var textsJSON: [String: Any] { Self.textsJSON(of: state) }

    static func textsJSON(of state: [SelectedText]) -> [String: Any] {
        func entry(_ text: SelectedText) -> [String: Any] {
            var entry: [String: Any] = ["text": text.text]
            if let source = text.appName { entry["from"] = source }
            return entry
        }
        return state.count == 1 ? entry(state[0]) : ["texts": state.map(entry)]
    }

    /// Whether the texts are short enough to go in a trimmed request.
    var textsFitTrimmed: Bool { state.reduce(0) { $0 + $1.text.count } <= Self.trimmedTextLimit }

    /// The question as Jev takes it: its yes/no question (`noul`), a set of answers with no descriptions
    /// (`choice`), or levels in order (`score`).
    var questionJSON: [String: Any] { questionJSON(instructions: question) }

    private func questionJSON(instructions: Any) -> [String: Any] { Self.questionJSON(instructions: instructions, answers: answers) }

    static func questionJSON(instructions: Any, answers: DecisionAnswers) -> [String: Any] {
        switch answers.kind {
        case .yesNo:
            ["type": "noul", "instructions": instructions]
        case .choice:
            ["type": "choice", "instructions": instructions, "criteria": Dictionary(answers.options.map { ($0, NSNull()) }, uniquingKeysWith: { first, _ in first })]
        case .score:
            ["type": "score", "instructions": instructions, "criteria": answers.options]
        }
    }

    /// The request about the whole text.
    func body(model: String) -> [String: Any] {
        ["model": model, "state": stateJSON, "questions": [Self.questionID: questionJSON]]
    }

    /// The request about `count` items from `offset` on, a question each, named by its place: the question, which
    /// item it is about by its name in the state, and the item itself, as TypeSafe's docs ask questions about one
    /// item among many. Trimmed (`Provider.trimsDecisionState`), the state holds only the batch's items, which the
    /// questions name from 0, and the texts only when they are short (`trimmedTextLimit`), so each of Ollama's
    /// prompts, which carries the state and every question of the request, fits its 2,050 tokens. The questions
    /// keep their names by their place among all the items, so the reply reads the same either way.
    func body(model: String, itemsFrom offset: Int, count: Int, trimmed: Bool = false) -> [String: Any] {
        let end = min(offset + count, items.count)
        var state: [String: Any]
        if trimmed {
            state = textsFitTrimmed ? textsJSON : [:]
            state["items"] = Array(items[offset..<end])
        } else {
            state = stateJSON
        }
        var questions: [String: Any] = [:]
        for index in offset..<end {
            let place = trimmed ? index - offset : index
            questions[Self.itemID(index)] = questionJSON(instructions: ["question": question, "about": "items[\(place)]", "item": items[index]])
        }
        return ["model": model, "state": state, "questions": questions]
    }

    /// The request that asks `questions` about `state` at once, each named by its id, as the live decisions on the
    /// Context card do (see `LiveDecisions`); the reply names its answers the same way.
    static func body(model: String, state: [SelectedText], questions: [DecisionQuestion]) -> [String: Any] {
        var named: [String: Any] = [:]
        for question in questions {
            named[question.id] = questionJSON(instructions: question.question, answers: question.answers)
        }
        return ["model": model, "state": textsJSON(of: state), "questions": named]
    }
}

/// The System One endpoint, `POST /v1/systemone`, at TypeSafe, at OpenRouter, which serves Jev and other labs'
/// decision models over the same contract, or at Ollama on this Mac, which serves Nimble and Tev1 over it too: a
/// state and named questions in, and for each a typed answer with probabilities out, in one JSON body a few
/// hundred milliseconds later, never a stream. Meraline asks one question a request and reads its answer into a
/// `Decision`, with what the reply says it took, and cost when it says, for the usage ledger.
nonisolated enum DecisionClient {
    private static let session = URLSession(configuration: .ephemeral)

    /// What Test Connection asks, since it has no text of yours.
    static let probe = DecisionRequest(
        state: [SelectedText("Meraline is testing its connection to a decision model.")!],
        question: "Is this a test?",
        answers: .yesNo
    )

    /// One reply about the whole text, or, about each word or line, one for every hundred items, or as many as the
    /// provider takes (`Provider.questionsPerRequest`), the batch so far after each so the card fills as they come.
    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decision = request.decision ?? probe
                    let model = model(of: request.settings, provider: request.provider)
                    if decision.items.isEmpty {
                        let data = try await post(decision.body(model: model), about: decision.state, settings: request.settings, provider: request.provider)
                        let reply = try decode(data, for: decision.answers, from: request.provider)
                        continuation.yield(.usage(reply.usage, adds: false))
                        continuation.yield(.decision(reply.decision))
                    } else {
                        var batch = DecisionBatch(scope: decision.scope, answers: decision.answers, total: decision.items.count, items: [])
                        let size = request.provider.questionsPerRequest
                        for offset in stride(from: 0, to: decision.items.count, by: size) {
                            try Task.checkCancellation()
                            let body = decision.body(model: model, itemsFrom: offset, count: size, trimmed: request.provider.trimsDecisionState)
                            let data = try await post(body, about: decision.state, settings: request.settings, provider: request.provider)
                            let reply = try decodeBatch(data, for: decision, from: offset, count: size, provider: request.provider)
                            batch.items += reply.items
                            continuation.yield(.usage(reply.usage, adds: true))
                            continuation.yield(.decisions(batch))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The model from Settings, or the provider's default when none is set.
    static func model(of settings: ProviderSettings, provider: Provider) -> String {
        let model = settings.model.trimmed
        return model.isEmpty ? provider.defaultModel : model
    }

    /// Several questions about the same texts, answered in one request, or as many as the provider takes
    /// (`Provider.questionsPerRequest`), for the live decisions on the Context card (see `LiveDecisions`): every
    /// answer by its question's id, and what the requests took together.
    static func decide(_ questions: [DecisionQuestion], about state: [SelectedText], settings: ProviderSettings, provider: Provider) async throws -> LiveReply {
        let model = model(of: settings, provider: provider)
        var reply = LiveReply(decisions: [:], usage: .zero)
        for batch in batches(of: questions, for: provider) {
            try Task.checkCancellation()
            let data = try await post(DecisionRequest.body(model: model, state: state, questions: batch), about: state, settings: settings, provider: provider)
            let part = try decodeLive(data, for: batch, from: provider)
            reply.decisions.merge(part.decisions) { _, new in new }
            reply.usage = reply.usage.merging(part.usage, adding: true)
        }
        return reply
    }

    /// The questions in the groups that go in one request each: all of them for Jev and OpenRouter, eight at a
    /// time for Ollama, whose prompts carry every question of a request.
    static func batches(of questions: [DecisionQuestion], for provider: Provider) -> [[DecisionQuestion]] {
        let size = provider.questionsPerRequest
        return stride(from: 0, to: questions.count, by: size).map { Array(questions[$0..<min($0 + size, questions.count)]) }
    }

    /// Posts `body` and reads the reply, or throws with what the server said.
    private static func post(_ body: [String: Any], about state: [SelectedText], settings: ProviderSettings, provider: Provider) async throws -> Data {
        let (data, response) = try await session.data(for: urlRequest(body, about: state, settings: settings, provider: provider))
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.provider("The server sent a response Meraline doesn’t understand.")
        }
        guard (200..<300).contains(http.statusCode) else {
            Log.providers.error("\(provider.name) answered HTTP \(http.statusCode)")
            throw LLMError.http(http.statusCode, StreamDecoder.errorMessage(from: data))
        }
        return data
    }

    /// The HTTP request for `decision` about the whole text, with the key as a bearer token, when the provider
    /// takes one, and the model from Settings, or the provider's default when none is set.
    static func urlRequest(_ decision: DecisionRequest, settings: ProviderSettings, provider: Provider = .typeSafe) throws -> URLRequest {
        try urlRequest(decision.body(model: model(of: settings, provider: provider)), about: decision.state, settings: settings, provider: provider)
    }

    /// The HTTP request that asks `questions` about `state` at once (see `decide(_:about:settings:provider:)`).
    static func urlRequest(_ questions: [DecisionQuestion], about state: [SelectedText], settings: ProviderSettings, provider: Provider = .typeSafe) throws -> URLRequest {
        try urlRequest(DecisionRequest.body(model: model(of: settings, provider: provider), state: state, questions: questions), about: state, settings: settings, provider: provider)
    }

    private static func urlRequest(_ body: [String: Any], about state: [SelectedText], settings: ProviderSettings, provider: Provider) throws -> URLRequest {
        let key = settings.apiKey.trimmed
        if provider.keyPolicy == .required && key.isEmpty { throw LLMError.missingKey(provider) }
        guard !state.isEmpty else { throw LLMError.provider("A decision needs text to decide about.") }
        guard var components = URLComponents(string: settings.baseURL.trimmed),
              components.scheme == "https" || components.scheme == "http",
              components.host?.isEmpty == false else {
            throw LLMError.invalidBaseURL(settings.baseURL)
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = "\(basePath)/systemone"
        guard let url = components.url else { throw LLMError.invalidBaseURL(settings.baseURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // A model on this Mac loads into memory on its first request, which takes a while.
        request.timeoutInterval = provider.runsOnThisMac ? 120 : 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    struct Reply: Equatable, Sendable {
        let decision: Decision
        let usage: TokenUsage
    }

    struct BatchReply: Equatable, Sendable {
        let items: [DecisionBatch.Item]
        let usage: TokenUsage
    }

    /// The answers to several questions asked at once, by question id, and what they took.
    struct LiveReply: Equatable, Sendable {
        var decisions: [DecisionQuestion.ID: Decision]
        var usage: TokenUsage
    }

    /// The reply's answer about the whole text as a `Decision` over `answers`.
    static func decode(_ data: Data, for answers: DecisionAnswers, from provider: Provider = .typeSafe) throws -> Reply {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        guard let answer = response.answers[DecisionRequest.questionID] else { throw LLMError.emptyResponse }
        return Reply(decision: try decision(from: answer, for: answers, provider: provider), usage: usage(of: response))
    }

    /// The reply's answers about `count` items from `offset` on, each read as `decode` reads one, in their order.
    /// An item Jev didn't answer fails the batch.
    static func decodeBatch(_ data: Data, for request: DecisionRequest, from offset: Int, count: Int, provider: Provider = .typeSafe) throws -> BatchReply {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        var items: [DecisionBatch.Item] = []
        for index in offset..<min(offset + count, request.items.count) {
            guard let answer = response.answers[DecisionRequest.itemID(index)] else { throw LLMError.emptyResponse }
            items.append(DecisionBatch.Item(id: index, text: request.items[index], decision: try decision(from: answer, for: request.answers, provider: provider)))
        }
        return BatchReply(items: items, usage: usage(of: response))
    }

    /// The reply's answers to `questions`, each read as `decode` reads one, by the question's id. A question the
    /// model didn't answer fails the reply.
    static func decodeLive(_ data: Data, for questions: [DecisionQuestion], from provider: Provider = .typeSafe) throws -> LiveReply {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        var decisions: [DecisionQuestion.ID: Decision] = [:]
        for question in questions {
            guard let answer = response.answers[question.id] else { throw LLMError.emptyResponse }
            decisions[question.id] = try decision(from: answer, for: question.answers, provider: provider)
        }
        return LiveReply(decisions: decisions, usage: usage(of: response))
    }

    /// What the reply says it took: tokens, the cost when the server says (OpenRouter does), and the model.
    private static func usage(of response: SystemOneResponse) -> TokenUsage {
        TokenUsage(input: response.usage?.inputTokens, output: response.usage?.outputTokens, cost: response.usage?.cost, model: response.model)
    }

    /// An answer as a `Decision` over `answers`. A yes/no answer is one probability of yes, so No gets the rest
    /// and the confidence is worked out; a set's answer carries a probability for each option and Jev's
    /// confidence; levels come by their place, with the score along them.
    private static func decision(from answer: SystemOneResponse.Answer, for answers: DecisionAnswers, provider: Provider) throws -> Decision {
        let decision: Decision
        switch answer.type {
        case "noul":
            guard let noul = answer.noul else { throw LLMError.emptyResponse }
            let yes = min(max(noul, 0), 1)
            let options = answers.options.map { Decision.Option(label: $0, probability: $0.lowercased() == "yes" ? yes : 1 - yes) }
            decision = Decision(options: options, isYesNo: true, confidence: abs(2 * yes - 1))
        case "choice":
            guard let probabilities = answer.probabilities else { throw LLMError.emptyResponse }
            let options = answers.options.map { Decision.Option(label: $0, probability: probabilities[$0] ?? 0) }
            decision = Decision(options: options, confidence: answer.confidence ?? Decision.confidence(over: options.map(\.probability)))
        case "score":
            guard let probabilities = answer.probabilities else { throw LLMError.emptyResponse }
            let options = answers.options.enumerated().map { index, label in
                Decision.Option(label: label, probability: probabilities["\(index)"] ?? 0)
            }
            decision = Decision(options: options, isOrdered: true, score: answer.score, confidence: answer.confidence ?? Decision.confidence(over: options.map(\.probability)))
        default:
            throw LLMError.provider("\(provider.name) answered with a “\(answer.type)” question, which Meraline doesn’t know.")
        }
        return decision
    }

    private struct SystemOneResponse: Decodable {
        let model: String?
        let answers: [String: Answer]
        let usage: Usage?

        struct Answer: Decodable {
            let type: String
            let noul: Double?
            let choice: String?
            let score: Double?
            let confidence: Double?
            let probabilities: [String: Double]?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            /// In US dollars, which OpenRouter reports and TypeSafe doesn't.
            let cost: Double?

            private enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cost
            }
        }
    }
}
