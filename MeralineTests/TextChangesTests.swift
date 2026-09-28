import Foundation
import Testing
@testable import Meraline

struct TextChangesTests {
    @Test func aGrammarFixMarksEachWordThatChanged() throws {
        let changes = try #require(TextChanges.diff(from: "i has a apple", to: "I have an apple."))
        #expect(changes.segments == [
            .removed("i"), .added("I"), .same(" "),
            .removed("has"), .added("have"), .same(" "),
            .removed("a"), .added("an"), .same(" apple"),
            .added("."),
        ])
        #expect(changes.count == 4)
        #expect(changes.summary == "4 changes")
        #expect(changes.similarity >= TextChanges.minimumSimilarity)
        #expect(!changes.isCode)
    }

    @Test func aTypoInOneWordStillCounts() throws {
        let changes = try #require(TextChanges.find(in: "receive", against: ["recieve"]))
        #expect(changes.segments == [.removed("recieve"), .added("receive")])
        #expect(changes.summary == "1 change")
    }

    @Test func anAnswerAboutTheTextChangedNothing() {
        let original = "i has a apple"
        #expect(TextChanges.find(in: "It says someone owns an apple.", against: [original]) == nil)
        #expect(TextChanges.find(in: "J’ai une pomme.", against: [original]) == nil)
        #expect(TextChanges.find(in: "The sentence needs “have” after “I”, and “an” before a vowel.", against: [original]) == nil)
        let paragraph = "Our team met on Monday to plan the launch. We agreed to ship the beta in two weeks, after the last round of testing, and to write the release notes together."
        #expect(TextChanges.find(in: "The team plans a beta in two weeks.", against: [paragraph]) == nil, "a summary keeps too little")
    }

    @Test func theSameTextComesBackUnchanged() throws {
        let text = "Everything here is already fine."
        let changes = try #require(TextChanges.find(in: text, against: [text]))
        #expect(changes.segments == [.same(text)])
        #expect(changes.count == 0)
        #expect(changes.summary == "No changes")
        #expect(changes.similarity == 1)
    }

    @Test func spacingForSpacingShowsTheNewSpacing() throws {
        let changes = try #require(TextChanges.diff(from: "one  two\nthree", to: "one two three"))
        #expect(changes.segments == [.same("one two three")])
        #expect(changes.count == 0)
        #expect(changes.changesSpacing)
        #expect(changes.summary == "Only the spacing changed")

        let joined = try #require(TextChanges.diff(from: "Hello , world", to: "Hello, world"))
        #expect(joined.segments == [.same("Hello"), .removed(" "), .same(", world")], "a space that goes still shows")
        #expect(joined.count == 1)
    }

    @Test func theTextInACodeBlockIsWhatIsCompared() throws {
        let answer = """
        Here's the fix:

        ```
        I have an apple.
        ```

        The verb agrees with “I” now.
        """
        let changes = try #require(TextChanges.find(in: answer, against: ["I has a apple"]))
        #expect(changes.isCode)
        #expect(changes.segments.first == .same("I "))
        #expect(!changes.segments.contains { if case .added(let text) = $0 { text.contains("`") || text.contains("verb") } else { false } })
    }

    @Test func aLineThatIntroducesTheTextIsLeftOut() throws {
        let changes = try #require(TextChanges.find(in: "Here's the corrected text:\n\nI have an apple.", against: ["I has a apple"]))
        #expect(changes.segments == [.same("I "), .removed("has"), .added("have"), .same(" "), .removed("a"), .added("an"), .same(" apple"), .added(".")])
    }

    @Test func aQuoteIsOneOfTheParts() {
        let parts = TextChanges.parts(of: "Try this:\n\n> I have an apple.\n> And a pear.\n\nThat reads better.")
        #expect(parts.map(\.text).contains("I have an apple.\nAnd a pear."))
        #expect(parts.map(\.text).contains("> I have an apple.\n> And a pear.\n\nThat reads better."))
    }

    @Test func theTextTheAnswerKeepsTheMostOfIsTheOneCompared() throws {
        let changes = try #require(TextChanges.find(in: "I have an apple.", against: ["The weather is nice today, and tomorrow too.", "i has a apple"]))
        #expect(changes.segments.first == .removed("i"))
    }

    @Test func wordsKeepTheirApostrophesAndSpacelessScriptsGoACharacterAtATime() {
        #expect(TextChanges.tokens(in: "don't stop, rock’n’roll") == ["don't", " ", "stop", ",", " ", "rock’n’roll"])
        #expect(TextChanges.tokens(in: "'quoted'") == ["'", "quoted", "'"])
        #expect(TextChanges.tokens(in: "我爱你。") == ["我", "爱", "你", "。"])
        #expect(TextChanges.tokens(in: "snake_case  x2\n") == ["snake_case", "  ", "x2", "\n"])
    }

    @Test func theChangesSpellOutBothTexts() throws {
        let original = "The quick brown fox, it jumps over the lazy dog!\nThen it sleeps."
        let revised = "A quick red fox jumps over the dog.\nThen it sleeps soundly."
        let changes = try #require(TextChanges.diff(from: original, to: revised))
        var old = ""
        var new = ""
        for segment in changes.segments {
            switch segment {
            case .same(let text):
                old += text
                new += text
            case .removed(let text): old += text
            case .added(let text): new += text
            }
        }
        #expect(new == revised)
        #expect(old == original)
    }

    @Test func theStepsAreAShortestWay() {
        var generator = Generator(seed: 7)
        for _ in 0..<400 {
            let a = (0..<Int.random(in: 0...24, using: &generator)).map { _ in Int.random(in: 0..<4, using: &generator) }
            var b = a
            for _ in 0..<Int.random(in: 0...8, using: &generator) {
                switch Int.random(in: 0..<3, using: &generator) {
                case 0 where !b.isEmpty: b.remove(at: Int.random(in: 0..<b.count, using: &generator))
                case 1: b.insert(Int.random(in: 0..<5, using: &generator), at: Int.random(in: 0...b.count, using: &generator))
                case 2 where !b.isEmpty: b[Int.random(in: 0..<b.count, using: &generator)] = Int.random(in: 0..<5, using: &generator)
                default: break
                }
            }
            if Int.random(in: 0..<5, using: &generator) == 0 { b = (0..<Int.random(in: 0...20, using: &generator)).map { _ in Int.random(in: 0..<4, using: &generator) } }

            guard let steps = TextChanges.steps(from: a, to: b, limit: 1_000) else {
                Issue.record("no steps from \(a) to \(b)")
                continue
            }
            var i = 0
            var j = 0
            var kept = 0
            for step in steps {
                switch step {
                case .keep:
                    #expect(a[i] == b[j])
                    i += 1
                    j += 1
                    kept += 1
                case .remove: i += 1
                case .add: j += 1
                }
            }
            #expect(i == a.count && j == b.count)
            let common = Self.longestCommonSubsequence(a, b)
            #expect(kept == common, "\(a) → \(b)")
            let edits = a.count + b.count - 2 * common
            #expect(TextChanges.steps(from: a, to: b, limit: edits) != nil)
            if edits > 0 { #expect(TextChanges.steps(from: a, to: b, limit: edits - 1) == nil) }
        }
    }

    @Test func textRearrangedThroughoutIsNotCompared() {
        let lines = (0..<3_000).map { "item \($0)" }
        #expect(TextChanges.diff(from: lines.joined(separator: "\n"), to: lines.reversed().joined(separator: "\n")) == nil)
    }

    @Test func aLongTextWithAFewFixes() throws {
        let sentence = "The committee reviewed the proposal carefully and agreed to revisit it next quarter."
        var sentences = Array(repeating: sentence, count: 230)
        let original = sentences.joined(separator: " ")
        #expect(original.count <= SelectedText.limit)
        sentences[10] = sentence.replacingOccurrences(of: "carefully", with: "thoroughly")
        sentences[120] = sentence.replacingOccurrences(of: "agreed", with: "decided")
        sentences[229] = sentence.replacingOccurrences(of: "next", with: "last")
        let changes = try #require(TextChanges.find(in: sentences.joined(separator: " "), against: [original]))
        #expect(changes.count == 3)
        #expect(changes.segments.contains(.added("thoroughly")))
        #expect(changes.segments.contains(.added("last")))
    }

    // MARK: Helpers

    private static func longestCommonSubsequence(_ a: [Int], _ b: [Int]) -> Int {
        var row = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var diagonal = 0
            for (index, y) in b.enumerated() {
                let above = row[index + 1]
                row[index + 1] = x == y ? diagonal + 1 : max(above, row[index])
                diagonal = above
            }
        }
        return row[b.count]
    }

    /// The same numbers every run.
    private struct Generator: RandomNumberGenerator {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }
}
