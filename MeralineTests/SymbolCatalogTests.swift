import AppKit
import Testing
@testable import Meraline

/// The icon picker's search over the SF Symbols this Mac has: the words people type find the icons they mean.
struct SymbolCatalogTests {
    private let catalog = SymbolCatalog.shared

    private func top(_ query: String, _ count: Int = 5) -> [String] {
        Array(catalog.search(query).prefix(count))
    }

    @Test func macOSsCatalogIsRead() throws {
        let catalog = try #require(SymbolCatalog.system())
        #expect(catalog.symbols.count > 3000)
        #expect(catalog.categories.contains { $0.title == "Communication" && $0.names.contains("envelope") })
        #expect(catalog.categories.allSatisfy { !$0.names.isEmpty })
        #expect(catalog.current("doc.text") == "text.document")
    }

    /// Variants for other scripts and right to left are macOS's to pick, so the picker shows each symbol once.
    @Test func variantsForOtherScriptsAreLeftOut() {
        let names = Set(catalog.symbols.map(\.name))
        #expect(names.contains("character.book.closed"))
        #expect(!names.contains("character.book.closed.ja"))
        #expect(!names.contains("0.circle.ar"))
        #expect(names.contains("arrow.up"))
    }

    @Test func aNameFindsItsSymbolFirst() {
        #expect(top("envelope").first == "envelope")
        #expect(top("star").first == "star")
        #expect(top("trash").first == "trash")
        #expect(top("pencil.and.scribble").first == "pencil.and.scribble")
        // An old name finds the symbol it became.
        #expect(top("doc.text").first == "text.document")
        #expect(top("wand.and.stars").first == "wand.and.sparkles")
    }

    /// Words Apple's keywords don't know find what they mean through `related`.
    @Test func everydayWordsFindTheirIcons() {
        #expect(top("email", 2).contains("envelope"))
        #expect(top("mail", 3).contains("envelope"))
        #expect(top("urgent", 2).contains("exclamationmark.triangle"))
        #expect(top("money", 3).contains("dollarsign.circle"))
        #expect(top("idea", 1) == ["lightbulb"])
        #expect(top("chat", 5).contains("bubble.left.and.bubble.right"))
        #expect(top("bug", 2).contains("ant"))
        #expect(top("scam", 3).contains("exclamationmark.shield"))
        #expect(top("summary", 5).contains("list.bullet.rectangle"))
        #expect(top("ai", 2).contains("sparkles"))
        #expect(top("code", 5).contains("chevron.left.forwardslash.chevron.right"))
        #expect(top("translate", 1) == ["translate"])
        #expect(top("tone", 3).contains("face.smiling"))
    }

    @Test func pluralsTensesAndHalfTypedWordsFindTheirIcons() {
        #expect(top("emails", 2).contains("envelope"))
        #expect(top("translating", 3).contains("translate"))
        #expect(top("ema", 3).contains("envelope"))
        #expect(top("light", 10).contains("lightbulb"))
        #expect(top("pen", 2).contains("pencil"))
    }

    @Test func everyWordOfTheQueryHasToMatch() {
        #expect(top("face smiling", 1) == ["face.smiling"])
        #expect(catalog.search("envelope qwxz").isEmpty)
    }

    @Test func nothingFindsNothing() {
        #expect(catalog.search("").isEmpty)
        #expect(catalog.search("   ").isEmpty)
        #expect(catalog.search("qwxzv").isEmpty)
    }

    /// Two letters find whole words only, so "ai" never brings up airplane.
    @Test func shortWordsFindWholeWords() {
        #expect(!top("ai", 10).contains("airplane"))
        #expect(top("ok", 1) == ["checkmark"])
    }

    /// Every symbol `related` names is one macOS has, under its own name or the one this macOS gave it. CI runs
    /// macOS 26, which lacks the names macOS 27 brought (building.classical.columns).
    @Test func theRelatedSymbolsExist() throws {
        let catalog = try #require(SymbolCatalog.system())
        let names = Set(catalog.symbols.map(\.name))
        for (word, symbols) in SymbolCatalog.related {
            for symbol in symbols {
                #expect(names.contains(catalog.current(symbol)), "\(word): \(symbol)")
            }
        }
    }

    /// Without macOS's catalog the picker still searches the Suggested icons by name and everyday words.
    @Test func theSuggestedIconsAloneAreSearchedToo() {
        let catalog = SymbolCatalog(names: PromptPreset.symbols)
        #expect(catalog.search("eraser").first == "eraser")
        #expect(catalog.search("email").contains("envelope"))
        #expect(catalog.categories.isEmpty)
    }

    /// A search runs as each letter is typed, so it has to be quick.
    @Test func aSearchIsQuick() {
        _ = catalog.search("warm up")
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for query in ["e", "em", "ema", "emai", "email", "face smiling", "translating"] {
                _ = catalog.search(query)
            }
        }
        #expect(elapsed < .milliseconds(700), "\(elapsed)")
    }
}
