import Foundation

/// What a model charges, in US dollars a token, as OpenRouter lists it. Cached prompt tokens cost the prompt
/// price when the model lists none for them.
nonisolated struct ModelPrice: Codable, Equatable, Sendable {
    var prompt: Double
    var completion: Double
    var cacheRead: Double?
    var cacheWrite: Double?

    /// A model that runs on this Mac.
    static let free = ModelPrice(prompt: 0, completion: 0)
    /// TypeSafe's list price for Jev, $0.042 a million tokens in and nothing out, which OpenRouter's list doesn't
    /// carry.
    static let jev = ModelPrice(prompt: 0.042 / 1_000_000, completion: 0)

    func cost(of tokens: UsageTally.ModelTally.Tokens) -> Double {
        let input = Double(tokens.input) * prompt
        let output = Double(tokens.output) * completion
        let read = Double(tokens.cacheRead) * (cacheRead ?? prompt)
        let write = Double(tokens.cacheWrite) * (cacheWrite ?? prompt)
        return input + output + read + write
    }
}

/// OpenRouter's public prices for the models it routes to, which are the labs' own list prices, fetched from
/// https://openrouter.ai/api/v1/models without a key and kept with the usage ledger. A model Meraline talks to
/// directly is looked up by its lab and name, so an Anthropic key's claude-sonnet-4-5-20250929 finds
/// anthropic/claude-sonnet-4.5.
nonisolated struct PriceTable: Codable, Equatable, Sendable {
    /// By OpenRouter's id, such as openai/gpt-5-mini; its batch and alias variants are left out.
    var prices: [String: ModelPrice]
    var fetched: Date

    static let source = URL(string: "https://openrouter.ai/api/v1/models")!

    /// How long a table is trusted before it is fetched again.
    static let lifetime: TimeInterval = 24 * 3_600

    var isStale: Bool { fetched.timeIntervalSinceNow < -Self.lifetime }

    /// Reads OpenRouter's list. A price of -1 means the price depends on the route, so such a model is skipped.
    static func parse(_ data: Data) throws -> PriceTable {
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        var prices: [String: ModelPrice] = [:]
        for model in list.data {
            guard !model.id.hasPrefix("~"), !model.id.contains(":"),
                  let prompt = model.pricing.prompt.flatMap(Double.init), prompt >= 0,
                  let completion = model.pricing.completion.flatMap(Double.init), completion >= 0 else { continue }
            let cacheRead = model.pricing.inputCacheRead.flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil }
            let cacheWrite = model.pricing.inputCacheWrite.flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil }
            prices[model.id] = ModelPrice(prompt: prompt, completion: completion, cacheRead: cacheRead, cacheWrite: cacheWrite)
        }
        return PriceTable(prices: prices, fetched: .now)
    }

    static func fetch(with session: URLSession = URLSession(configuration: .ephemeral)) async throws -> PriceTable {
        var request = URLRequest(url: source)
        request.timeoutInterval = 20
        request.setValue("Meraline", forHTTPHeaderField: "X-Title")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(http.statusCode, "OpenRouter couldn’t list its models.")
        }
        return try parse(data)
    }

    /// The price of `model` at `provider`: a model on this Mac is free, OpenRouter's own ids are looked up as
    /// they are, and the others by their lab and name, dates and dots aside. Nil when the table has no such
    /// model, and the answer waits unpriced.
    func price(for provider: Provider, model: String) -> ModelPrice? {
        if provider.isOnDevice || provider == .ollama { return .free }
        if provider.isDecisionModel { return .jev }
        let model = model.trimmed
        guard !model.isEmpty else { return nil }
        if provider == .openRouter || provider == .opencode || provider == .custom {
            if let exact = prices[model] ?? prices[String(model.prefix { $0 != ":" })] { return exact }
        }
        let wanted = Self.normalized(model.contains("/") ? String(model[model.index(after: model.firstIndex(of: "/")!)...]) : model)
        let vendors = Self.vendors(of: provider)
        let candidates = prices.keys.filter { id in
            guard let slash = id.firstIndex(of: "/") else { return false }
            let vendor = String(id[..<slash])
            guard vendors.isEmpty || vendors.contains(vendor) else { return false }
            return Self.normalized(String(id[id.index(after: slash)...])) == wanted
        }
        guard let id = candidates.sorted().min(by: { $0.count < $1.count }) else { return nil }
        return prices[id]
    }

    /// OpenRouter's name for the lab behind a provider; any for one that could route anywhere.
    private static func vendors(of provider: Provider) -> [String] {
        switch provider {
        case .anthropic, .claudeCode: ["anthropic"]
        case .openAI, .codex: ["openai"]
        case .gemini: ["google"]
        case .openRouter, .custom, .opencode, .ollama, .apple, .typeSafe: []
        }
    }

    /// A model's name as the labs and OpenRouter can both be read: lower case, without a "models/" prefix, a
    /// date suffix, or "-latest", and with dots as dashes, so claude-sonnet-4-5-20250929 reads as
    /// claude-sonnet-4-5, as anthropic/claude-sonnet-4.5 does.
    static func normalized(_ name: String) -> String {
        var name = name.lowercased().trimmed
        if name.hasPrefix("models/") { name.removeFirst("models/".count) }
        if let range = name.range(of: #"-\d{4}-?\d{2}-?\d{2}$"#, options: .regularExpression) { name.removeSubrange(range) }
        if name.hasSuffix("-latest") { name.removeLast("-latest".count) }
        return name.replacingOccurrences(of: ".", with: "-")
    }

    private struct ModelList: Decodable {
        let data: [Model]
    }

    private struct Model: Decodable {
        let id: String
        let pricing: Pricing
    }

    private struct Pricing: Decodable {
        let prompt: String?
        let completion: String?
        let inputCacheRead: String?
        let inputCacheWrite: String?

        private enum CodingKeys: String, CodingKey {
            case prompt, completion
            case inputCacheRead = "input_cache_read"
            case inputCacheWrite = "input_cache_write"
        }
    }
}
