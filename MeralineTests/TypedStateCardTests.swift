import AppKit
import SwiftUI
import Testing
@testable import Meraline

/// The card Tab opens for context written in the window (`TypedStateCard`).
@MainActor
struct TypedStateCardTests {
    /// The editor draws its first line at its very top, with no inset of its own, and the placeholder is drawn over
    /// it by SwiftUI; once they disagreed, the caret blinked a line's gap above “Paste or type…”. The placeholder's
    /// letters have to fall within the caret's height, where typed text draws.
    @Test func theCaretStartsOnThePlaceholdersLine() async throws {
        for isDeciding in [false, true] {
            var text = ""
            let binding = Binding(get: { text }, set: { text = $0 })
            let focus = FocusState<Bool>()
            let host = NSHostingView(rootView: TypedStateCard(text: binding, isDeciding: isDeciding, isFocused: focus.projectedValue, remove: {}).frame(width: 600))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()

            let textView = try #require(Self.textView(in: host))
            let caret = window.convertFromScreen(textView.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil))
            #expect(caret.height > 10)

            // The placeholder's ink, in window points (up is larger), in the field's rows, right of the caret.
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsHigh) / host.bounds.height
            let field = textView.convert(textView.bounds, to: nil)
            var ink: [CGFloat] = []
            for row in 0..<rep.pixelsHigh {
                let y = host.bounds.height - CGFloat(row) / scale
                guard y <= field.maxY + 4, y >= field.minY - 4 else { continue }
                let dark = stride(from: Int((caret.minX + 1) * scale), to: Int(300 * scale), by: 1)
                    .filter { (rep.colorAt(x: $0, y: row)?.alphaComponent ?? 0) > 0.05 }.count
                if dark > 2 { ink.append(y) }
            }
            let top = try #require(ink.max())
            let bottom = try #require(ink.min())
            #expect(top <= caret.maxY && bottom >= caret.minY - 1, "placeholder drawn from \(bottom) to \(top), caret from \(caret.minY) to \(caret.maxY)")
        }
    }

    private static func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap(textView(in:)).first
    }
}
