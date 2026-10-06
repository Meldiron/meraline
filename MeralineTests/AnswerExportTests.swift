import AppKit
import Testing
@testable import Meraline

/// An answer copied or inserted whole goes to the pasteboard as its Markdown and, beside it, as HTML and RTF, so
/// an app that takes rich text pastes bold, lists, code, and tables as such. Until 2026-10-06 TextEdit got the
/// asterisks and dashes.
struct AnswerExportTests {
    private static let answer = """
    # Coffee

    A **cortado** is espresso cut with *warm milk*, about `1:1`. See [the guide](https://example.com/guide) and ~~this~~.

    - Cortado: strong
      - a nested note
    - Latte: mild

    1. First
    2. Second

    > A quote with **bold**.

    ```swift
    let shots = 1 < 2 && "a" > "b"
    ```

    | Drink | Milk |
    | --- | --- |
    | Cortado | a little |
    | Latte | a lot |

    ---

    <script>alert("x")</script> & done.
    """

    @Test func htmlIsPlainAndSemantic() {
        let html = AnswerExport.html(Self.answer)
        #expect(html.contains("<h1>Coffee</h1>"))
        #expect(html.contains("<p>A <strong>cortado</strong> is espresso cut with <em>warm milk</em>, about <code>1:1</code>. See <a href=\"https://example.com/guide\">the guide</a> and <s>this</s>.</p>"))
        #expect(html.contains("<ul><li>Cortado: strong<ul><li>a nested note</li></ul></li><li>Latte: mild</li></ul>"))
        #expect(html.contains("<ol><li>First</li><li>Second</li></ol>"))
        #expect(html.contains("<blockquote><p>A quote with <strong>bold</strong>.</p></blockquote>"))
        #expect(html.contains("<pre><code class=\"language-swift\">let shots = 1 &lt; 2 &amp;&amp; &quot;a&quot; &gt; &quot;b&quot;</code></pre>"))
        #expect(html.contains("<table><thead><tr><th>Drink</th><th>Milk</th></tr></thead><tbody><tr><td>Cortado</td><td>a little</td></tr><tr><td>Latte</td><td>a lot</td></tr></tbody></table>"))
        #expect(html.contains("<hr>"))
        #expect(html.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; done."), "what an answer quotes is text")
        #expect(!html.contains("<script>"))
        #expect(!html.contains("style=") && !html.contains("font"), "no fonts, sizes, or colors: the editor keeps its own")
    }

    @Test func rtfKeepsTheShapeOfTheAnswer() throws {
        let data = try #require(AnswerExport.rtf(Self.answer))
        let read = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        let text = read.string
        #expect(text.hasPrefix("Coffee\n"))
        #expect(text.contains("A cortado is espresso cut with warm milk, about 1:1. See the guide and this."))
        #expect(text.contains("•\tCortado: strong\n•\ta nested note\n•\tLatte: mild\n\n1.\tFirst\n2.\tSecond"), "the lists stand apart, as in the Markdown")
        #expect(text.contains("let shots = 1 < 2 && \"a\" > \"b\""))
        #expect(text.contains("Drink\tMilk\nCortado\ta little\nLatte\ta lot"), "a table as tab-separated rows")
        let row = (text as NSString).range(of: "Cortado\ta little")
        let style = read.attribute(.paragraphStyle, at: row.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.tabStops.count == 2, "a tab stop a column, at its widest cell, so the columns line up")
        #expect((style?.tabStops.first?.location ?? 0) > 40)
        #expect(text.contains("<script>alert(\"x\")</script> & done."))

        func font(at word: String) -> NSFont? {
            let range = (text as NSString).range(of: word)
            return read.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        }
        #expect(font(at: "cortado")?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font(at: "warm milk")?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(font(at: "1:1")?.familyName == "Menlo")
        #expect(font(at: "let shots")?.familyName == "Menlo")
        #expect(font(at: "espresso")?.familyName == "Helvetica")
        #expect(font(at: "espresso")?.pointSize == 12)
        #expect((font(at: "Coffee")?.pointSize ?? 0) > 12 && font(at: "Coffee")?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let link = (text as NSString).range(of: "the guide")
        #expect(read.attribute(.link, at: link.location, effectiveRange: nil) as? URL == URL(string: "https://example.com/guide"))
    }

    @Test func thePasteboardItemCarriesAllThreeForms() {
        let item = NSPasteboardItem()
        AnswerExport.write("Say **hi**", to: item)
        #expect(Set(item.types) == [.string, .html, .rtf])
        #expect(item.string(forType: .string) == "Say **hi**", "the Markdown, exactly as before")
        #expect(item.string(forType: .html) == "<p>Say <strong>hi</strong></p>")
        #expect(item.data(forType: .rtf) != nil)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MeralineTests.\(UUID().uuidString)"))
        AnswerExport.copy("Plain", to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Plain")
        #expect(pasteboard.string(forType: .html) == "<p>Plain</p>")
        #expect(pasteboard.pasteboardItems?.count == 1)
        pasteboard.releaseGlobally()
    }
}
