import Foundation
import Testing
@testable import Meraline

struct PricingTests {
    /// A few lines of OpenRouter's list: batch and alias variants, a model priced by route, and a missing cache price.
    static let list = """
    {"data":[
      {"id":"anthropic/claude-sonnet-4.5","name":"Claude Sonnet 4.5","pricing":{"prompt":"0.000003","completion":"0.000015","input_cache_read":"0.0000003","input_cache_write":"0.00000375"}},
      {"id":"anthropic/claude-sonnet-4.5:batch","pricing":{"prompt":"0.0000015","completion":"0.0000075"}},
      {"id":"~anthropic/claude-sonnet-latest","pricing":{"prompt":"0.000003","completion":"0.000015"}},
      {"id":"anthropic/claude-haiku-4.5","pricing":{"prompt":"0.000001","completion":"0.000005","input_cache_read":"0.0000001","input_cache_write":"0.00000125"}},
      {"id":"openai/gpt-5-mini","pricing":{"prompt":"0.00000025","completion":"0.000002","input_cache_read":"0.000000025"}},
      {"id":"openai/gpt-5-mini-2025-08-07","pricing":{"prompt":"0.00000025","completion":"0.000002"}},
      {"id":"google/gemini-2.5-flash","pricing":{"prompt":"0.0000003","completion":"0.0000025","input_cache_read":"0.00000003","input_cache_write":"0.0000000833"}},
      {"id":"meta-llama/llama-3.3-70b-instruct","pricing":{"prompt":"0.0000001","completion":"0.0000003"}},
      {"id":"openrouter/auto","pricing":{"prompt":"-1","completion":"-1"}},
      {"id":"mistralai/mistral-small","pricing":{"prompt":"bad","completion":"0.0000003"}}
    ]}
    """

    private var table: PriceTable {
        try! PriceTable.parse(Data(Self.list.utf8))
    }

    @Test func theListIsReadWithoutItsVariants() throws {
        let table = table
        #expect(table.prices.count == 6, "no batch, alias, priced-by-route, or unreadable models")
        let sonnet = try #require(table.prices["anthropic/claude-sonnet-4.5"])
        #expect(sonnet == ModelPrice(prompt: 0.000003, completion: 0.000015, cacheRead: 0.0000003, cacheWrite: 0.00000375))
        #expect(table.prices["openai/gpt-5-mini"]?.cacheWrite == nil)
        #expect(!table.isStale)
        #expect(PriceTable(prices: [:], fetched: .now.addingTimeInterval(-2 * 24 * 3_600)).isStale)
        #expect(throws: (any Error).self) { try PriceTable.parse(Data("not json".utf8)) }
        #expect(try PriceTable.parse(Data(#"{"data":[]}"#.utf8)).prices.isEmpty)
    }

    @Test func modelsAreFoundByTheirLabAndName() {
        let table = table
        let sonnet = table.prices["anthropic/claude-sonnet-4.5"]
        #expect(table.price(for: .anthropic, model: "claude-sonnet-4-5-20250929") == sonnet, "dates and dots aside")
        #expect(table.price(for: .anthropic, model: "claude-sonnet-4.5") == sonnet)
        #expect(table.price(for: .anthropic, model: "claude-sonnet-4-5-latest") == sonnet)
        #expect(table.price(for: .claudeCode, model: "claude-haiku-4-5-20251001") == table.prices["anthropic/claude-haiku-4.5"])
        #expect(table.price(for: .openAI, model: "gpt-5-mini") == table.prices["openai/gpt-5-mini"])
        #expect(table.price(for: .openAI, model: "gpt-5-mini-2025-08-07") == table.prices["openai/gpt-5-mini"], "the shortest of the ids that read alike")
        #expect(table.price(for: .codex, model: "gpt-5-mini") == table.prices["openai/gpt-5-mini"])
        #expect(table.price(for: .gemini, model: "models/gemini-2.5-flash") == table.prices["google/gemini-2.5-flash"])
        #expect(table.price(for: .openRouter, model: "google/gemini-2.5-flash") == table.prices["google/gemini-2.5-flash"], "OpenRouter's own ids as they are")
        #expect(table.price(for: .openRouter, model: "google/gemini-2.5-flash:nitro") == table.prices["google/gemini-2.5-flash"])
        #expect(table.price(for: .opencode, model: "anthropic/claude-sonnet-4.5") == sonnet)
        #expect(table.price(for: .custom, model: "llama-3.3-70b-instruct") == table.prices["meta-llama/llama-3.3-70b-instruct"], "any lab, by name")
        #expect(table.price(for: .anthropic, model: "gpt-5-mini") == nil, "not another lab's model")
        #expect(table.price(for: .openAI, model: "gpt-9") == nil)
        #expect(table.price(for: .codex, model: "") == nil, "an agent's default model has no name to look up")
        #expect(table.price(for: .ollama, model: "llama3.2") == .free)
        #expect(table.price(for: .apple, model: "") == .free)
        #expect(PriceTable.normalized("Models/Gemini-2.5-Flash-Latest") == "gemini-2-5-flash")
        #expect(PriceTable.normalized("claude-3-5-sonnet-20241022") == "claude-3-5-sonnet")
    }

    @Test func tokensAreCostedAtThePrice() {
        let price = ModelPrice(prompt: 0.000003, completion: 0.000015, cacheRead: 0.0000003, cacheWrite: 0.00000375)
        let tokens = UsageTally.ModelTally.Tokens(input: 1_000_000, output: 100_000, cacheRead: 1_000_000, cacheWrite: 200_000)
        #expect(abs(price.cost(of: tokens) - (3 + 1.5 + 0.3 + 0.75)) < 1e-9)
        let plain = ModelPrice(prompt: 0.000002, completion: 0.00001)
        #expect(abs(plain.cost(of: UsageTally.ModelTally.Tokens(cacheRead: 1_000_000)) - 2) < 1e-9, "cached tokens at the prompt price when the model lists none")
        #expect(ModelPrice.free.cost(of: tokens) == 0)
    }

    @Test func answersAreCostedAsTheyComeOrWhenATableArrives() {
        var tally = UsageTally()
        let key = "anthropic/claude-sonnet-4.5"
        let price = ModelPrice(prompt: 0.000003, completion: 0.000015)
        tally.count(answer: TokenUsage(input: 1_000, output: 100), reported: true, for: key, price: price)
        tally.count(answer: TokenUsage(input: 1_000, output: 100), reported: true, for: key, price: nil)
        tally.count(answer: TokenUsage(input: 10, output: 10, cost: 0.5), reported: true, for: key, price: price)
        let model = tally.models[key]!
        #expect(model.pricedAnswers == 1 && model.costedAnswers == 1 && model.unpricedAnswers == 1)
        #expect(abs(model.cost - (0.003 + 0.0015 + 0.5)) < 1e-9, "the provider's cost stands over the price")
        #expect(model.unpriced == .init(input: 1_000, output: 100))
        #expect(abs(model.cost(pricedAt: price) - (0.5 + 2 * 0.0045)) < 1e-9, "priced now")
        #expect(abs(model.cost(pricedAt: nil) - (0.5 + 0.0045)) < 1e-9)

        let costs = tally.cost(pricedBy: { $0 == key ? price : nil })
        #expect(abs(costs.total - (0.5 + 2 * 0.0045)) < 1e-9 && costs.unpricedAnswers == 0)
        let unknown = tally.cost(pricedBy: { _ in nil })
        #expect(abs(unknown.total - (0.5 + 0.0045)) < 1e-9 && unknown.unpricedAnswers == 1)
    }

    @Test func anOlderFileReadsWithItsMissingFieldsAtZero() throws {
        let data = Data(#"{"questions":3,"models":{"openai/gpt-5":{"answers":2,"input":40}},"games":{"rhymeDuel":{"started":1}}}"#.utf8)
        let tally = try JSONDecoder().decode(UsageTally.self, from: data)
        #expect(tally.questions == 3 && tally.answers == 0 && tally.rewrites.isEmpty)
        #expect(tally.models["openai/gpt-5"] == .init(answers: 2, input: 40))
        #expect(tally.games["rhymeDuel"] == .init(started: 1))
        let round = try JSONDecoder().decode(UsageTally.self, from: JSONEncoder().encode(tally))
        #expect(round == tally)
    }

    @MainActor
    @Test func theLedgerFetchesPricesOnceADayAndKeepsThem() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.\(UUID().uuidString)")
        let file = folder.appending(path: "usage.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let ledger = UsageLedger(file: file)
        #expect(ledger.price(for: .ollama, model: "llama3.2") == .free, "free without a table")
        #expect(ledger.price(for: .anthropic, model: "claude-sonnet-4.5") == nil)

        var fetches = 0
        let table = table
        await ledger.refreshPrices { fetches += 1; return table }
        #expect(fetches == 1 && ledger.prices == table && ledger.pricesFailure == nil)
        await ledger.refreshPrices { fetches += 1; return table }
        #expect(fetches == 1, "a fresh table is kept")
        await ledger.refreshPrices(force: true) { fetches += 1; throw LLMError.emptyResponse }
        #expect(fetches == 2 && ledger.prices == table, "a failed fetch keeps the table")
        #expect(ledger.pricesFailure == LLMError.emptyResponse.localizedDescription)
        #expect(ledger.price(for: .anthropic, model: "claude-sonnet-4-5-20250929") == table.prices["anthropic/claude-sonnet-4.5"])
        #expect(ledger.price(forKey: "claudeCode/claude-haiku-4-5-20251001") == table.prices["anthropic/claude-haiku-4.5"])
        #expect(ledger.price(forKey: "codex") == nil)

        await ledger.save()
        let again = UsageLedger(file: file)
        #expect(again.prices == table, "kept with the ledger")
        again.clear()
        #expect(again.prices == table, "and not cleared with it")
    }
}
