import AppKit

/// An answer as the pasteboard carries it when it is copied or inserted whole: its Markdown as plain text, as
/// before, and beside it the same answer as HTML and as RTF, so an app that takes rich text pastes bold,
/// lists, code, and tables as such instead of the asterisks and dashes. The HTML is plain and semantic, with no
/// fonts, sizes, or colors, so web-based editors keep their own style; the RTF is for AppKit text views, in
/// Helvetica 12 with Menlo for code. Both come from the answer's blocks (`MarkdownBlock`) and inline Markdown,
/// never through WebKit.
nonisolated enum AnswerExport {
    static let html = NSPasteboard.PasteboardType.html
    static let rtf = NSPasteboard.PasteboardType.rtf

    /// Writes the answer to `item` in its three forms.
    static func write(_ markdown: String, to item: NSPasteboardItem) {
        item.setString(markdown, forType: .string)
        item.setString(html(markdown), forType: html)
        if let data = rtf(markdown) { item.setData(data, forType: rtf) }
    }

    /// Puts the answer on `pasteboard` in its three forms, in place of whatever was there.
    static func copy(_ markdown: String, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        write(markdown, to: item)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    // MARK: HTML

    static func html(_ markdown: String) -> String {
        html(of: MarkdownBlock.blocks(in: markdown))
    }

    private static func html(of blocks: [MarkdownBlock]) -> String {
        var parts: [String] = []
        var index = 0
        while index < blocks.count {
            switch blocks[index] {
            case .paragraph(let text):
                parts.append("<p>\(inlineHTML(text))</p>")
            case .heading(let level, let text):
                let tag = "h\(min(max(level, 1), 6))"
                parts.append("<\(tag)>\(inlineHTML(text))</\(tag)>")
            case .list(let items):
                parts.append(listHTML(items))
            case .quote(let inner):
                parts.append("<blockquote>\(html(of: inner))</blockquote>")
            case .code(let code):
                let language = code.language.map { " class=\"language-\(escaped($0))\"" } ?? ""
                parts.append("<pre><code\(language)>\(escaped(code.code))</code></pre>")
            case .table(let table):
                parts.append(tableHTML(table))
            case .rule:
                parts.append("<hr>")
            }
            index += 1
        }
        return parts.joined(separator: "\n")
    }

    /// A list as nested `<ul>` and `<ol>`, from the items' depths: a deeper item opens a list inside the one
    /// before it, and a shallower one closes lists back to its depth.
    private static func listHTML(_ items: [MarkdownBlock.ListItem]) -> String {
        var out = ""
        var open: [String] = []
        func opens(_ item: MarkdownBlock.ListItem) -> String {
            if case .number = item.marker { return "ol" }
            return "ul"
        }
        for item in items {
            while open.count > item.depth + 1 {
                out += "</li></\(open.removeLast())>"
            }
            if open.count == item.depth + 1 {
                // The next item of the same list, or a list of the other kind right after it, which the blocks
                // read as one list.
                if open.last == opens(item) {
                    out += "</li>"
                } else {
                    out += "</li></\(open.removeLast())>"
                    let tag = opens(item)
                    out += "<\(tag)>"
                    open.append(tag)
                }
            } else {
                while open.count < item.depth + 1 {
                    let tag = opens(item)
                    out += "<\(tag)>"
                    open.append(tag)
                }
            }
            let text: String
            switch item.marker {
            case .task(let done): text = "\(done ? "☑" : "☐") \(inlineHTML(item.text))"
            default: text = inlineHTML(item.text)
            }
            out += "<li>\(text)"
        }
        while let tag = open.popLast() {
            out += "</li></\(tag)>"
        }
        return out
    }

    private static func tableHTML(_ table: MarkdownBlock.Table) -> String {
        func cells(_ row: [String], tag: String) -> String {
            row.map { "<\(tag)>\(inlineHTML($0))</\(tag)>" }.joined()
        }
        var out = "<table><thead><tr>\(cells(table.header, tag: "th"))</tr></thead>"
        if !table.rows.isEmpty {
            out += "<tbody>" + table.rows.map { "<tr>\(cells($0, tag: "td"))</tr>" }.joined() + "</tbody>"
        }
        return out + "</table>"
    }

    /// A block's text with its inline Markdown as HTML: bold, italics, code spans, strikethrough, and links,
    /// everything else escaped, so a `<script>` an answer quotes is text.
    static func inlineHTML(_ text: String) -> String {
        var out = ""
        let rendered = MarkdownText.render(text)
        for run in rendered.runs {
            let piece = escaped(String(rendered[run.range].characters))
            var opened: [String] = []
            if let link = run.link {
                out += "<a href=\"\(escaped(link.absoluteString))\">"
                opened.append("a")
            }
            let intent = run.inlinePresentationIntent ?? []
            for (flag, tag) in [(InlinePresentationIntent.stronglyEmphasized, "strong"), (.emphasized, "em"), (.code, "code"), (.strikethrough, "s")] where intent.contains(flag) {
                out += "<\(tag)>"
                opened.append(tag)
            }
            out += piece
            for tag in opened.reversed() { out += "</\(tag)>" }
        }
        return out.replacingOccurrences(of: "\n", with: "<br>")
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: RTF

    static func rtf(_ markdown: String) -> Data? {
        let text = attributed(markdown)
        return try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// The answer as rich text: Helvetica 12 with bold and italics, Menlo for code, bullets and numbers for lists,
    /// headings larger and bold, quotes indented, a table as tab-separated rows, and a rule as a line of dashes.
    static func attributed(_ markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        append(MarkdownBlock.blocks(in: markdown), to: out, indent: 0)
        return out
    }

    private static let bodySize: CGFloat = 12

    private static func append(_ blocks: [MarkdownBlock], to out: NSMutableAttributedString, indent: CGFloat) {
        for (index, block) in blocks.enumerated() {
            // A blank line between blocks, as the Markdown has, so paragraphs, lists, and tables stand apart.
            if index > 0 { out.append(NSAttributedString(string: "\n\n", attributes: [.font: font(size: bodySize)])) }
            switch block {
            case .paragraph(let text):
                out.append(inline(text, size: bodySize, indent: indent))
            case .heading(let level, let text):
                let size = bodySize + [6, 4, 2][min(max(level, 1), 3) - 1]
                out.append(inline(text, size: size, bold: true, indent: indent))
            case .list(let items):
                var numbers: [Int: Int] = [:]
                for (place, item) in items.enumerated() {
                    if place > 0 {
                        // A list of the other kind right after this one, which the blocks read as one list, stands apart.
                        let newList = item.depth == 0 && Self.isNumbered(item) != Self.isNumbered(items[place - 1]) && items[place - 1].depth == 0
                        out.append(NSAttributedString(string: newList ? "\n\n" : "\n", attributes: [.font: font(size: bodySize)]))
                    }
                    let marker: String
                    switch item.marker {
                    case .bullet: marker = "•"
                    case .number: numbers[item.depth, default: 0] += 1; marker = "\(numbers[item.depth]!)."
                    case .task(let done): marker = done ? "☑" : "☐"
                    }
                    for deeper in numbers.keys where deeper > item.depth { numbers[deeper] = nil }
                    let line = NSMutableAttributedString(string: "\(marker)\t", attributes: [.font: font(size: bodySize)])
                    line.append(inline(item.text, size: bodySize, indent: 0))
                    let style = NSMutableParagraphStyle()
                    let head = indent + 20 * CGFloat(item.depth + 1)
                    style.firstLineHeadIndent = head - 14
                    style.headIndent = head
                    style.tabStops = [NSTextTab(textAlignment: .left, location: head)]
                    line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
                    out.append(line)
                }
            case .quote(let inner):
                append(inner, to: out, indent: indent + 20)
            case .code(let code):
                let style = NSMutableParagraphStyle()
                style.headIndent = indent
                style.firstLineHeadIndent = indent
                out.append(NSAttributedString(string: code.code, attributes: [.font: NSFont(name: "Menlo", size: bodySize - 1) ?? .monospacedSystemFont(ofSize: bodySize - 1, weight: .regular), .paragraphStyle: style]))
            case .table(let table):
                // Tab-separated rows, with a tab stop at each column's widest cell, so the columns line up.
                let rows = [table.header] + table.rows
                let columns = rows.map(\.count).max() ?? 0
                var stops: [NSTextTab] = []
                var edge = indent
                for column in 0..<columns {
                    let widest = rows.compactMap { column < $0.count ? inline($0[column], size: bodySize, bold: true, indent: 0).size().width : nil }.max() ?? 0
                    edge += widest.rounded(.up) + 16
                    stops.append(NSTextTab(textAlignment: .left, location: edge))
                }
                let style = NSMutableParagraphStyle()
                style.headIndent = indent
                style.firstLineHeadIndent = indent
                style.tabStops = stops
                for (place, row) in rows.enumerated() {
                    if place > 0 { out.append(NSAttributedString(string: "\n")) }
                    let line = NSMutableAttributedString()
                    for (column, cell) in row.enumerated() {
                        if column > 0 { line.append(NSAttributedString(string: "\t", attributes: [.font: font(size: bodySize)])) }
                        line.append(inline(cell, size: bodySize, bold: place == 0, indent: 0))
                    }
                    line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
                    out.append(line)
                }
            case .rule:
                out.append(NSAttributedString(string: String(repeating: "—", count: 12), attributes: [.font: font(size: bodySize), .foregroundColor: NSColor.gray]))
            }
        }
    }

    private static func isNumbered(_ item: MarkdownBlock.ListItem) -> Bool {
        if case .number = item.marker { return true }
        return false
    }

    /// A block's text with its inline Markdown as attributes.
    private static func inline(_ text: String, size: CGFloat, bold: Bool = false, indent: CGFloat) -> NSAttributedString {
        let rendered = MarkdownText.render(text)
        let out = NSMutableAttributedString()
        for run in rendered.runs {
            let piece = String(rendered[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var attributes: [NSAttributedString.Key: Any] = [:]
            if intent.contains(.code) {
                attributes[.font] = NSFont(name: "Menlo", size: size - 1) ?? .monospacedSystemFont(ofSize: size - 1, weight: .regular)
            } else {
                attributes[.font] = font(size: size, bold: bold || intent.contains(.stronglyEmphasized), italic: intent.contains(.emphasized))
            }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            out.append(NSAttributedString(string: piece, attributes: attributes))
        }
        if indent > 0 {
            let style = NSMutableParagraphStyle()
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        }
        return out
    }

    private static func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return NSFontManager.shared.font(withFamily: "Helvetica", traits: traits, weight: bold ? 9 : 5, size: size)
            ?? NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
    }
}
