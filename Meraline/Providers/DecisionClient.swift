import Foundation

/// A question for TypeSafe's Jev (see `DecisionClient`): the texts it is about, which go as the request's state,
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

    /// Jev's state: the text with the app it came from, or the texts in order, and the words or lines when the
    /// question is about each.
    var stateJSON: [String: Any] {
        func entry(_ text: SelectedText) -> [String: Any] {
            var entry: [String: Any] = ["text": text.text]
            if let source = text.appName { entry["from"] = source }
            return entry
        }
        var json: [String: Any] = state.count == 1 ? entry(state[0]) : ["texts": state.map(entry)]
        if !items.isEmpty { json["items"] = items }
        return json
    }

    /// The question as Jev takes it: its yes/no question (`noul`), a set of answers with no descriptions
    /// (`choice`), or levels in order (`score`).
    var questionJSON: [String: Any] { questionJSON(instructions: question) }

    private func questionJSON(instructions: Any) -> [String: Any] {
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
    /// item among many.
    func body(model: String, itemsFrom offset: Int, count: Int) -> [String: Any] {
        var questions: [String: Any] = [:]
        for index in offset..<min(offset + count, items.count) {
            questions[Self.itemID(index)] = questionJSON(instructions: ["question": question, "about": "items[\(index)]", "item": items[index]])
        }
        return ["model": model, "state": stateJSON, "questions": questions]
    }
}

/// TypeSafe's one endpoint, `POST /v1/systemone`: a state and named questions in, and for each a typed answer with
/// probabilities out, in one JSON body a few hundred milliseconds later, never a stream. Meraline asks one question
/// a request and reads its answer into a `Decision`, with what the reply says it took for the usage ledger.
nonisolated enum DecisionClient {
    private static let session = URLSession(configuration: .ephemeral)

    /// What Test Connection asks, since it has no text of yours.
    static let probe = DecisionRequest(
        state: [SelectedText("Meraline is testing its connection to TypeSafe.")!],
        question: "Is this a test?",
        answers: .yesNo
    )

    /// One reply about the whole text, or, about each word or line, one for every hundred items, the batch so far
    /// after each so the card fills as they come.
    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decision = request.decision ?? probe
                    let model = model(of: request.settings, provider: request.provider)
                    if decision.items.isEmpty {
                        let data = try await post(decision.body(model: model), for: decision, settings: request.settings, provider: request.provider)
                        let reply = try decode(data, for: decision.answers)
                        continuation.yield(.usage(reply.usage, adds: false))
                        continuation.yield(.decision(reply.decision))
                    } else {
                        var batch = DecisionBatch(scope: decision.scope, answers: decision.answers, total: decision.items.count, items: [])
                        for offset in stride(from: 0, to: decision.items.count, by: DecisionScope.batchSize) {
                            try Task.checkCancellation()
                            let body = decision.body(model: model, itemsFrom: offset, count: DecisionScope.batchSize)
                            let data = try await post(body, for: decision, settings: request.settings, provider: request.provider)
                            let reply = try decodeBatch(data, for: decision, from: offset, count: DecisionScope.batchSize)
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

    /// Posts `body` and reads the reply, or throws with what the server said.
    private static func post(_ body: [String: Any], for decision: DecisionRequest, settings: ProviderSettings, provider: Provider) async throws -> Data {
        let (data, response) = try await session.data(for: urlRequest(body, for: decision, settings: settings, provider: provider))
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.provider("The server sent a response Meraline doesn’t understand.")
        }
        guard (200..<300).contains(http.statusCode) else {
            Log.providers.error("\(provider.name) answered HTTP \(http.statusCode)")
            throw LLMError.http(http.statusCode, StreamDecoder.errorMessage(from: data))
        }
        return data
    }

    /// The HTTP request for `decision` about the whole text, with the key as a bearer token and the model from
    /// Settings, or the provider's default when none is set.
    static func urlRequest(_ decision: DecisionRequest, settings: ProviderSettings, provider: Provider = .typeSafe) throws -> URLRequest {
        try urlRequest(decision.body(model: model(of: settings, provider: provider)), for: decision, settings: settings, provider: provider)
    }

    private static func urlRequest(_ body: [String: Any], for decision: DecisionRequest, settings: ProviderSettings, provider: Provider) throws -> URLRequest {
        let key = settings.apiKey.trimmed
        guard !key.isEmpty else { throw LLMError.missingKey(provider) }
        guard !decision.state.isEmpty else { throw LLMError.provider("A decision needs text to decide about.") }
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
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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

    /// The reply's answer about the whole text as a `Decision` over `answers`.
    static func decode(_ data: Data, for answers: DecisionAnswers) throws -> Reply {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        guard let answer = response.answers[DecisionRequest.questionID] else { throw LLMError.emptyResponse }
        return Reply(decision: try decision(from: answer, for: answers), usage: usage(of: response))
    }

    /// The reply's answers about `count` items from `offset` on, each read as `decode` reads one, in their order.
    /// An item Jev didn't answer fails the batch.
    static func decodeBatch(_ data: Data, for request: DecisionRequest, from offset: Int, count: Int) throws -> BatchReply {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        var items: [DecisionBatch.Item] = []
        for index in offset..<min(offset + count, request.items.count) {
            guard let answer = response.answers[DecisionRequest.itemID(index)] else { throw LLMError.emptyResponse }
            items.append(DecisionBatch.Item(id: index, text: request.items[index], decision: try decision(from: answer, for: request.answers)))
        }
        return BatchReply(items: items, usage: usage(of: response))
    }

    private static func usage(of response: SystemOneResponse) -> TokenUsage {
        TokenUsage(input: response.usage?.inputTokens, output: response.usage?.outputTokens, model: response.model)
    }

    /// An answer as a `Decision` over `answers`. A yes/no answer is one probability of yes, so No gets the rest
    /// and the confidence is worked out; a set's answer carries a probability for each option and Jev's
    /// confidence; levels come by their place, with the score along them.
    private static func decision(from answer: SystemOneResponse.Answer, for answers: DecisionAnswers) throws -> Decision {
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
            throw LLMError.provider("TypeSafe answered with a “\(answer.type)” question, which Meraline doesn’t know.")
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

            private enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }
}
