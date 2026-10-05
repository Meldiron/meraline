import AppKit
import SwiftUI
import Testing
@testable import Meraline

/// How a table in an answer shares the room the card gives it: the widest columns give way first, down to a
/// floor, and only a table that can't fit even then scrolls sideways. A table of three everyday columns once
/// reached 840 points and scrolled, with its last column cut off.
@MainActor
struct TableColumnsTests {
    @Test func columnsThatFitKeepTheirWidths() {
        #expect(TableColumns.widths(natural: [100, 200, 150], room: 600, narrowest: 120) == [100, 200, 150])
        #expect(TableColumns.widths(natural: [100, 200, 300], room: 600, narrowest: 120) == [100, 200, 300], "exactly the room")
        #expect(TableColumns.widths(natural: [], room: 600, narrowest: 120) == [])
    }

    @Test func theWidestColumnsGiveWayFirst() {
        // 260 + 260 + 260 in 600: the three are cut to 200 each.
        #expect(TableColumns.widths(natural: [260, 260, 260], room: 600, narrowest: 120) == [200, 200, 200])
        // A narrow column keeps its width; the two wide ones share what is left.
        #expect(TableColumns.widths(natural: [80, 260, 260], room: 600, narrowest: 120) == [80, 260, 260])
        #expect(TableColumns.widths(natural: [80, 260, 260], room: 500, narrowest: 120) == [80, 210, 210])
        // Only the widest is cut while cutting it alone is enough.
        #expect(TableColumns.widths(natural: [100, 150, 260], room: 450, narrowest: 120) == [100, 150, 200])
        let widths = TableColumns.widths(natural: [60, 180, 260, 260], room: 600, narrowest: 120)
        #expect(widths == [60, 180, 180, 180])
        #expect(widths.reduce(0, +) == 600)
    }

    @Test func noColumnGoesBelowTheFloorSoAWideTableStillScrolls() {
        let widths = TableColumns.widths(natural: Array(repeating: 260, count: 12), room: 600, narrowest: 120)
        #expect(widths == Array(repeating: 120, count: 12), "twelve columns at the floor")
        #expect(widths.reduce(0, +) > 600, "wider than the room, so the table scrolls")
        #expect(TableColumns.widths(natural: [40, 260, 260, 260, 260], room: 500, narrowest: 120) == [40, 120, 120, 120, 120], "a column narrower than the floor stays as it is")
    }

    /// The horizontal scroll views under `view`, a table's among them.
    private func scrollViews(under view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews(under:))
    }

    /// The table of `markdown` laid out in a card `width` points wide, the room the conversation gives an answer:
    /// how wide its grid is and how much of it shows.
    private func layOut(_ markdown: String, width: CGFloat) -> (grid: CGFloat, shown: CGFloat) {
        let host = NSHostingView(rootView: MarkdownView(markdown: markdown).frame(width: width))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Measured once, the columns are sized to the room and laid out again.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        host.layoutSubtreeIfNeeded()
        let table = scrollViews(under: host).first { $0.documentView?.frame.width ?? 0 > 0 }
        return (table?.documentView?.frame.width ?? 0, table?.contentView.bounds.width ?? 0)
    }

    @Test func aTableOfThreeColumnsWrapsToTheCardAndOneOfTwelveScrolls() {
        let cortado = """
        | | Cortado | Latte |
        | --- | --- | --- |
        | Milk | Small amount, steamed (not foamy) | Large amount, steamed with a layer of foam |
        | Milk:Espresso Ratio | ~1:1 | ~3:1 or more |
        | Texture | Smooth, less foam | Creamy, with foam layer |
        """
        let three = layOut(cortado, width: 596)
        #expect(three.grid > 0)
        #expect(three.grid <= three.shown, "three columns fit the card: \(three.grid) in \(three.shown)")

        let header = "| " + (1...12).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let rule = "| " + Array(repeating: "---", count: 12).joined(separator: " | ") + " |"
        let row = "| " + (1...12).map { "A long cell number \($0) in a wide table" }.joined(separator: " | ") + " |"
        let twelve = layOut([header, rule, row, row].joined(separator: "\n"), width: 596)
        #expect(twelve.grid > twelve.shown, "twelve columns can't fit even at the floor, so the table scrolls")
    }
}
