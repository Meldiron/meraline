import Foundation

/// A question for TypeSafe's Jev (see `DecisionClient`): the texts it is about, which go as the request's state,
/// the question, less the answers it named, and the answers it picks from (see `DecisionAnswers`).
nonisolated struct DecisionRequest: Equatable, Sendable {
    let state: [SelectedText]
    let question: String
    let answers: DecisionAnswers

    /// The one question's name in the request and in the reply.
    static let questionID = "decision"

    /// Jev's state: the text with the app it came from, or the texts in order.
    var stateJSON: [String: Any] {
        func entry(_ text: SelectedText) -> [String: Any] {
            var entry: [String: Any] = ["text": text.text]
            if let source = text.appName { entry["from"] = source }
            return entry
        }
        if state.count == 1 { return entry(state[0]) }
        return ["texts": state.map(entry)]
    }

    /// The question as Jev takes it: its yes/no question (`noul`), a set of answers with no descriptions
    /// (`choice`), or levels in order (`score`).
    var questionJSON: [String: Any] {
        switch answers.kind {
        case .yesNo:
            ["type": "noul", "instructions": question]
        case .choice:
            ["type": "choice", "instructions": question, "criteria": Dictionary(answers.options.map { ($0, NSNull()) }, uniquingKeysWith: { first, _ in first })]
        case .score:
            ["type": "score", "instructions": question, "criteria": answers.options]
        }
    }

    func body(model: String) -> [String: Any] {
        ["model": model, "state": stateJSON, "questions": [Self.questionID: questionJSON]]
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

    static func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decision = request.decision ?? probe
                    let (data, response) = try await session.data(for: urlRequest(decision, settings: request.settings, provider: request.provider))
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.provider("The server sent a response Meraline doesn’t understand.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        Log.providers.error("\(request.provider.name) answered HTTP \(http.statusCode)")
                        throw LLMError.http(http.statusCode, StreamDecoder.errorMessage(from: data))
                    }
                    let reply = try decode(data, for: decision.answers)
                    continuation.yield(.usage(reply.usage, adds: false))
                    continuation.yield(.decision(reply.decision))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The HTTP request for `decision`, with the key as a bearer token and the model from Settings, or the
    /// provider's default when none is set.
    static func urlRequest(_ decision: DecisionRequest, settings: ProviderSettings, provider: Provider = .typeSafe) throws -> URLRequest {
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
        let model = settings.model.trimmed
        request.httpBody = try JSONSerialization.data(withJSONObject: decision.body(model: model.isEmpty ? provider.defaultModel : model))
        return request
    }

    struct Reply: Equatable, Sendable {
        let decision: Decision
        let usage: TokenUsage
    }

    /// The reply's answer as a `Decision` over `answers`. A yes/no answer is one probability of yes, so No gets
    /// the rest and the confidence is worked out; a set's answer carries a probability for each option and Jev's
    /// confidence; levels come by their place, with the score along them.
    static func decode(_ data: Data, for answers: DecisionAnswers) throws -> Reply {
        let response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        guard let answer = response.answers[DecisionRequest.questionID] else { throw LLMError.emptyResponse }
        let usage = TokenUsage(input: response.usage?.inputTokens, output: response.usage?.outputTokens, model: response.model)
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
        return Reply(decision: decision, usage: usage)
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
