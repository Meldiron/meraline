import AppKit
import SwiftUI

/// An answer's Markdown read into blocks: paragraphs, headings, lists, quotes, code, tables, and rules. Inline
/// Markdown (bold, code spans, links) stays in each block's text for `MarkdownText` to render. The reading is
/// forgiving, since answers stream in: a code fence not closed yet runs to the end, and a table shows once its
/// second line has come.
nonisolated enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case list([ListItem])
    case quote([MarkdownBlock])
    case code(CodeBlock)
    case table(Table)
    case rule

    struct ListItem: Equatable, Sendable {
        enum Marker: Equatable, Sendable {
            case bullet
            case number(Int)
            case task(done: Bool)
        }

        /// How deep the item sits in its list, from 0.
        let depth: Int
        let marker: Marker
        let text: String
    }

    struct CodeBlock: Equatable, Sendable {
        /// The fence's language, such as "swift", if it names one.
        let language: String?
        let code: String
    }

    struct Table: Equatable, Sendable {
        enum Alignment: Equatable, Sendable {
            case leading
            case center
            case trailing
        }

        let header: [String]
        let alignments: [Alignment]
        /// Each as wide as the header, padded or cut.
        let rows: [[String]]
    }

    /// Every code block in the Markdown, quotes included, in order.
    static func codeBlocks(in markdown: String) -> [CodeBlock] {
        func collect(_ blocks: [MarkdownBlock]) -> [CodeBlock] {
            blocks.flatMap { block -> [CodeBlock] in
                switch block {
                case .code(let code): [code]
                case .quote(let inner): collect(inner)
                default: []
                }
            }
        }
        return collect(blocks(in: markdown))
    }

    static func blocks(in markdown: String) -> [MarkdownBlock] {
        var reader = Reader(lines: markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"))
        return reader.read()
    }

    private struct Reader {
        let lines: [String]
        var index = 0
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        init(lines: [String]) {
            self.lines = lines
        }

        mutating func read() -> [MarkdownBlock] {
            while index < lines.count {
                let line = lines[index]
                if line.trimmed.isEmpty {
                    flushParagraph()
                    index += 1
                } else if let fence = Self.fence(in: line) {
                    flushParagraph()
                    readCode(fence)
                } else if let heading = Self.heading(in: line) {
                    flushParagraph()
                    blocks.append(heading)
                    index += 1
                } else if Self.isRule(line) {
                    flushParagraph()
                    blocks.append(.rule)
                    index += 1
                } else if index + 1 < lines.count, line.contains("|"), let alignments = Self.tableAlignments(in: lines[index + 1]),
                          Self.tableCells(in: line).count == alignments.count {
                    flushParagraph()
                    readTable(alignments)
                } else if Self.listItem(in: line) != nil {
                    flushParagraph()
                    readList()
                } else if Self.quoted(line) != nil {
                    flushParagraph()
                    readQuote()
                } else {
                    paragraph.append(line)
                    index += 1
                }
            }
            flushParagraph()
            return blocks
        }

        private mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        // MARK: Code

        private struct Fence {
            let marker: Character
            let length: Int
            let indent: Int
            let language: String?
        }

        private static func fence(in line: String) -> Fence? {
            let indent = line.prefix { $0 == " " }.count
            guard indent <= 3 else { return nil }
            let rest = line.dropFirst(indent)
            guard let marker = rest.first, marker == "`" || marker == "~" else { return nil }
            let length = rest.prefix { $0 == marker }.count
            guard length >= 3 else { return nil }
            let info = String(rest.dropFirst(length)).trimmed
            if marker == "`" && info.contains("`") { return nil }
            let language = info.split(separator: " ").first.map(String.init)
            return Fence(marker: marker, length: length, indent: indent, language: language)
        }

        /// The lines up to the closing fence, or to the end while the answer is still coming.
        private mutating func readCode(_ fence: Fence) {
            index += 1
            var code: [String] = []
            while index < lines.count {
                let line = lines[index]
                index += 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.count >= fence.length, trimmed.allSatisfy({ $0 == fence.marker }) { break }
                let indent = min(fence.indent, line.prefix { $0 == " " }.count)
                code.append(String(line.dropFirst(indent)))
            }
            blocks.append(.code(CodeBlock(language: fence.language, code: code.joined(separator: "\n"))))
        }

        // MARK: Headings and rules

        private static func heading(in line: String) -> MarkdownBlock? {
            let trimmed = line.drop { $0 == " " }
            let level = trimmed.prefix { $0 == "#" }.count
            guard (1...6).contains(level) else { return nil }
            let rest = trimmed.dropFirst(level)
            guard rest.isEmpty || rest.first == " " else { return nil }
            var text = String(rest).trimmed
            // A closing run of #s is decoration.
            while text.hasSuffix("#") { text.removeLast() }
            return .heading(level: level, text: text.trimmed)
        }

        private static func isRule(_ line: String) -> Bool {
            let characters = line.filter { $0 != " " && $0 != "\t" }
            guard characters.count >= 3, let first = characters.first, "-*_".contains(first) else { return false }
            return characters.allSatisfy { $0 == first }
        }

        // MARK: Tables

        /// The alignment row under a table's header, `| --- | :---: |`, or nil when the line isn't one.
        private static func tableAlignments(in line: String) -> [Table.Alignment]? {
            let cells = tableCells(in: line)
            guard !cells.isEmpty, line.contains("|"), line.contains("-") else { return nil }
            var alignments: [Table.Alignment] = []
            for cell in cells {
                let cell = cell.trimmed
                let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
                switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                case (true, true): alignments.append(.center)
                case (false, true): alignments.append(.trailing)
                default: alignments.append(.leading)
                }
            }
            return alignments
        }

        /// A row's cells, without the pipes at either end. `\|` stays in the cell as a pipe.
        private static func tableCells(in line: String) -> [String] {
            var line = line.trimmed
            if line.hasPrefix("|") { line.removeFirst() }
            if line.hasSuffix("|") && !line.hasSuffix("\\|") { line.removeLast() }
            var cells: [String] = []
            var cell = ""
            var escaped = false
            for character in line {
                if escaped {
                    cell.append(character == "|" ? "|" : "\\\(character)")
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "|" {
                    cells.append(cell.trimmed)
                    cell = ""
                } else {
                    cell.append(character)
                }
            }
            if escaped { cell.append("\\") }
            cells.append(cell.trimmed)
            return cells
        }

        private mutating func readTable(_ alignments: [Table.Alignment]) {
            let header = Self.tableCells(in: lines[index])
            let width = header.count
            index += 2
            var rows: [[String]] = []
            while index < lines.count, !lines[index].trimmed.isEmpty, lines[index].contains("|") {
                let cells = Self.tableCells(in: lines[index])
                rows.append(Array((cells + Array(repeating: "", count: max(0, width - cells.count))).prefix(width)))
                index += 1
            }
            let fitted = Array((alignments + Array(repeating: .leading, count: max(0, width - alignments.count))).prefix(width))
            blocks.append(.table(Table(header: header, alignments: fitted, rows: rows)))
        }

        // MARK: Lists

        private struct Item {
            let indent: Int
            let marker: ListItem.Marker
            let text: String
        }

        private static func listItem(in line: String) -> Item? {
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let rest = line.drop { $0 == " " || $0 == "\t" }
            var marker: ListItem.Marker
            var body: Substring
            if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
                marker = .bullet
                body = rest.dropFirst(2)
            } else {
                let digits = rest.prefix { $0.isASCII && $0.isNumber }
                guard (1...9).contains(digits.count) else { return nil }
                let after = rest.dropFirst(digits.count)
                guard let delimiter = after.first, delimiter == "." || delimiter == ")", after.dropFirst().first == " " else { return nil }
                marker = .number(Int(digits) ?? 1)
                body = after.dropFirst(2)
            }
            body = body.drop { $0 == " " }
            if marker == .bullet, body.count >= 3, body.hasPrefix("["), body.dropFirst(2).first == "]",
               let mark = body.dropFirst().first, mark == " " || mark == "x" || mark == "X" {
                marker = .task(done: mark != " ")
                body = body.dropFirst(3).drop { $0 == " " }
            }
            return Item(indent: indent, marker: marker, text: String(body))
        }

        /// Items and the lines that carry on under them, up to a line that starts something else. A blank line
        /// ends the list unless another item, or a line indented under one, comes next.
        private mutating func readList() {
            var items: [(indent: Int, marker: ListItem.Marker, text: [String])] = []
            while index < lines.count {
                let line = lines[index]
                if line.trimmed.isEmpty {
                    let next = lines[(index + 1)...].first { !$0.trimmed.isEmpty }
                    guard let next, Self.listItem(in: next) != nil || next.hasPrefix("  ") else { break }
                    index += 1
                } else if let item = Self.listItem(in: line) {
                    items.append((item.indent, item.marker, [item.text]))
                    index += 1
                } else if Self.fence(in: line) != nil || Self.heading(in: line) != nil || Self.isRule(line) || Self.quoted(line) != nil {
                    break
                } else if !items.isEmpty {
                    items[items.count - 1].text.append(line.trimmed)
                    index += 1
                } else {
                    break
                }
            }
            // Depth follows the indents as they come: deeper than the item before nests one more, and going back
            // out returns to the depth of the indent it matches.
            var indents: [Int] = []
            let listed = items.map { item -> ListItem in
                while let last = indents.last, last > item.indent { indents.removeLast() }
                if indents.last.map({ $0 < item.indent }) ?? true { indents.append(item.indent) }
                return ListItem(depth: indents.count - 1, marker: item.marker, text: item.text.joined(separator: "\n"))
            }
            blocks.append(.list(listed))
        }

        // MARK: Quotes

        private static func quoted(_ line: String) -> Substring? {
            let rest = line.drop { $0 == " " }
            guard line.count - rest.count <= 3, rest.first == ">" else { return nil }
            let body = rest.dropFirst()
            return body.first == " " ? body.dropFirst() : body
        }

        private mutating func readQuote() {
            var inner: [String] = []
            while index < lines.count, let body = Self.quoted(lines[index]) {
                inner.append(String(body))
                index += 1
            }
            var reader = Reader(lines: inner)
            blocks.append(.quote(reader.read()))
        }
    }
}

/// Markdown drawn as blocks: text you can select in each, headings, lists with their markers, quotes, code in a
/// monospaced box with Copy, tables in a grid, and rules. Neutral like the rest of the panel. The environment's
/// `answerZoom` enlarges the text and the room around it, leaving the code boxes' language and Copy as they are.
struct MarkdownView: View {
    let markdown: String
    var fontSize: CGFloat = 15

    var body: some View {
        MarkdownBlocksView(blocks: MarkdownBlock.blocks(in: markdown), fontSize: fontSize)
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let fontSize: CGFloat

    @Environment(\.answerZoom) private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * zoom) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, isFirst: index == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case .paragraph(let text):
            InlineText(text: text, fontSize: fontSize)
        case .heading(let level, let text):
            InlineText(text: text, fontSize: fontSize + Self.headingGrowth(level), weight: level <= 2 ? .bold : .semibold)
                .padding(.top, isFirst ? 0 : 4 * zoom)
                .accessibilityAddTraits(.isHeader)
        case .list(let items):
            MarkdownListView(items: items, fontSize: fontSize)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 10 * zoom) {
                RoundedRectangle(cornerRadius: 1.5 * zoom)
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3 * zoom)
                MarkdownBlocksView(blocks: inner, fontSize: fontSize)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let code):
            CodeBlockView(code: code, fontSize: fontSize)
        case .table(let table):
            MarkdownTableView(table: table, fontSize: fontSize)
        case .rule:
            Divider()
                .padding(.vertical, 4 * zoom)
        }
    }

    private static func headingGrowth(_ level: Int) -> CGFloat {
        switch level {
        case 1: 5
        case 2: 3
        case 3: 1
        default: 0
        }
    }
}

/// A block's text with its inline Markdown, which can be selected and copied.
private struct InlineText: View {
    let text: String
    let fontSize: CGFloat
    var weight: Font.Weight = .regular

    @Environment(\.answerZoom) private var zoom

    var body: some View {
        Text(Self.render(text))
            .font(.system(size: fontSize * zoom, weight: weight))
            .lineSpacing(3 * zoom)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `MarkdownText`'s rendering, with a faint box behind code spans.
    static func render(_ text: String) -> AttributedString {
        var rendered = MarkdownText.render(text)
        for run in rendered.runs where run.inlinePresentationIntent?.contains(.code) == true {
            rendered[run.range].backgroundColor = Color.primary.opacity(0.07)
        }
        return rendered
    }
}

private struct MarkdownListView: View {
    let items: [MarkdownBlock.ListItem]
    let fontSize: CGFloat

    @Environment(\.answerZoom) private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * zoom) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 7 * zoom) {
                    marker(item)
                        .font(.system(size: fontSize * zoom).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 14 * zoom, alignment: .trailing)
                    InlineText(text: item.text, fontSize: fontSize)
                }
                .padding(.leading, CGFloat(item.depth) * 20 * zoom)
            }
        }
    }

    @ViewBuilder
    private func marker(_ item: MarkdownBlock.ListItem) -> some View {
        switch item.marker {
        case .bullet:
            Text(["•", "◦", "▪"][item.depth % 3])
        case .number(let number):
            Text("\(number).")
        case .task(let done):
            Image(systemName: done ? "checkmark.square" : "square")
                .accessibilityLabel(done ? "Done" : "Not done")
        }
    }
}

/// Code in a monospaced box that scrolls sideways rather than wrap, with its language and a Copy button above.
private struct CodeBlockView: View {
    let code: MarkdownBlock.CodeBlock
    let fontSize: CGFloat

    @Environment(\.answerZoom) private var zoom
    @State private var showsCopied = false
    @State private var copiedTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(code.language ?? "")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: copy) {
                    Label(showsCopied ? "Copied" : "Copy", systemImage: showsCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Copy this code")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.top, 6)
            ScrollView(.horizontal) {
                Text(code.code)
                    .font(.system(size: (fontSize - 2) * zoom, design: .monospaced))
                    .lineSpacing(2 * zoom)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(.horizontal, 12 * zoom)
                    .padding(.top, 4 * zoom)
                    .padding(.bottom, 12 * zoom)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(code.language.map { "\($0) code" } ?? "Code")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.code, forType: .string)
        Log.panel.info("Code block copied")
        copiedTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) { showsCopied = true }
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) { showsCopied = false }
        }
    }
}

/// A table in a grid, the header in bold, with hairlines between rows. Wide tables scroll sideways, and a long
/// cell wraps.
private struct MarkdownTableView: View {
    let table: MarkdownBlock.Table
    let fontSize: CGFloat

    @Environment(\.answerZoom) private var zoom

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, text in
                        cell(text, column: column, weight: .semibold)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, text in
                            cell(text, column: column, weight: .regular)
                        }
                    }
                }
            }
            .fixedSize()
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
            .padding(1)
        }
        .scrollIndicators(.automatic)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table")
    }

    private func cell(_ text: String, column: Int, weight: Font.Weight) -> some View {
        let alignment = table.alignments.indices.contains(column) ? table.alignments[column] : .leading
        return Text(InlineText.render(text))
            .font(.system(size: (fontSize - 1) * zoom, weight: weight))
            .multilineTextAlignment(alignment.text)
            .textSelection(.enabled)
            .frame(maxWidth: 260 * zoom, alignment: alignment.frame)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10 * zoom)
            .padding(.vertical, 6 * zoom)
            .gridColumnAlignment(alignment.horizontal)
    }
}

private extension MarkdownBlock.Table.Alignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var text: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
