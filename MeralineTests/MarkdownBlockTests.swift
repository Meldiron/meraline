import Testing
@testable import Meraline

struct MarkdownBlockTests {
    @Test func paragraphsKeepTheirLineBreaksAndSplitOnBlankLines() {
        let blocks = MarkdownBlock.blocks(in: "First line\nsecond line\n\nNext **paragraph**.")
        #expect(blocks == [.paragraph("First line\nsecond line"), .paragraph("Next **paragraph**.")])
    }

    @Test func headingsAndRules() {
        let blocks = MarkdownBlock.blocks(in: "# Title\n## Steps ##\n#hashtag\n\n---\n* * *")
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .heading(level: 2, text: "Steps"),
            .paragraph("#hashtag"),
            .rule,
            .rule,
        ])
    }

    @Test func fencedCodeKeepsItsLanguageAndIndentation() {
        let blocks = MarkdownBlock.blocks(in: "Run this:\n\n```swift\nlet x = 1\n    print(x)\n```\nDone.")
        #expect(blocks == [
            .paragraph("Run this:"),
            .code(.init(language: "swift", code: "let x = 1\n    print(x)")),
            .paragraph("Done."),
        ])
    }

    /// While an answer streams, a fence may not be closed yet; the code runs to the end instead of vanishing.
    @Test func anUnclosedFenceRunsToTheEnd() {
        let blocks = MarkdownBlock.blocks(in: "~~~\nhalf a script\n# not a heading")
        #expect(blocks == [.code(.init(language: nil, code: "half a script\n# not a heading"))])
    }

    @Test func listsNestByIndentAndKeepTheirNumbers() {
        let markdown = """
        1. Open Settings
           in the menu bar
        2. Pick a provider
           - Anthropic
           - [x] Ollama
        3. Ask
        """
        let blocks = MarkdownBlock.blocks(in: markdown)
        #expect(blocks == [.list([
            .init(depth: 0, marker: .number(1), text: "Open Settings\nin the menu bar"),
            .init(depth: 0, marker: .number(2), text: "Pick a provider"),
            .init(depth: 1, marker: .bullet, text: "Anthropic"),
            .init(depth: 1, marker: .task(done: true), text: "Ollama"),
            .init(depth: 0, marker: .number(3), text: "Ask"),
        ])])
    }

    @Test func aBlankLineEndsAListUnlessAnotherItemFollows() {
        let blocks = MarkdownBlock.blocks(in: "- one\n\n- two\n\nAfter the list.")
        #expect(blocks == [
            .list([.init(depth: 0, marker: .bullet, text: "one"), .init(depth: 0, marker: .bullet, text: "two")]),
            .paragraph("After the list."),
        ])
    }

    @Test func quotesHoldBlocksOfTheirOwn() {
        let blocks = MarkdownBlock.blocks(in: "> Note\n> - a point\n\nOutside")
        #expect(blocks == [
            .quote([.paragraph("Note"), .list([.init(depth: 0, marker: .bullet, text: "a point")])]),
            .paragraph("Outside"),
        ])
    }

    @Test func tablesReadTheirAlignmentsAndPadShortRows() {
        let markdown = """
        | Model | Price | Notes |
        |:------|------:|:-----:|
        | Opus | $5 | best \\| deepest |
        | Haiku | $1 |
        """
        let blocks = MarkdownBlock.blocks(in: markdown)
        #expect(blocks == [.table(.init(
            header: ["Model", "Price", "Notes"],
            alignments: [.leading, .trailing, .center],
            rows: [["Opus", "$5", "best | deepest"], ["Haiku", "$1", ""]]
        ))])
    }

    /// A pipe in a sentence followed by a rule is no table.
    @Test func aPipeInProseIsNotATable() {
        let blocks = MarkdownBlock.blocks(in: "Use a | b here\n---")
        #expect(blocks == [.paragraph("Use a | b here"), .rule])
    }

    @Test func codeBlocksAreFoundInQuotesToo() {
        let markdown = "```sh\nls\n```\n\n> ```\n> pwd\n> ```"
        #expect(MarkdownBlock.codeBlocks(in: markdown) == [
            .init(language: "sh", code: "ls"),
            .init(language: nil, code: "pwd"),
        ])
    }
}
