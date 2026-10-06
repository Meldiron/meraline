import AppKit
import SwiftUI
import Testing
@testable import Meraline

/// Where the conversation stands while an answer grows, in the app's own panel. It follows the answer's end
/// while the reader is there, and stays where the reader scrolled to otherwise: until 2026-10-06 every change of
/// the conversation's height scrolled to the bottom, so nobody could read a long answer's start while it
/// streamed, and follow-ups arriving pulled the reader down again.
@MainActor
struct ConversationScrollTests {
    private typealias Support = GameTestSupport
    private typealias Feed = AsyncThrowingStream<StreamOutput, Error>.Continuation

    private static func throwaway() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func paragraphs(_ range: ClosedRange<Int>) -> String {
        range.map { "Paragraph \($0). Meraline keeps every chat in memory and lets it go when its time runs out. This one is here to make the answer long." }
            .joined(separator: "\n\n") + "\n\n"
    }

    /// The scroll views under `view`, the conversation's among them.
    private func scrollViews(under view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews(under:))
    }

    /// Turns the scroll wheel over `scroll`, as a reader does: up for a positive `distance`, in points.
    private func wheel(_ scroll: NSScrollView, by distance: Int32) throws {
        var left = distance
        while left != 0 {
            let step = max(-80, min(80, left))
            let turn = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try #require(NSEvent(cgEvent: turn)))
            left -= step
        }
    }

    /// Lets the panel read its stream and lay itself out, for at most `seconds`, until `condition` holds.
    private func settle(_ seconds: TimeInterval = 5, until condition: () -> Bool = { false }) async {
        let deadline = Date(timeIntervalSinceNow: seconds)
        repeat {
            try? await Task.sleep(for: .milliseconds(40))
        } while !condition() && Date() < deadline
    }

    @Test func theConversationFollowsAnAnswersEndOnlyWhileTheReaderIsThere() async throws {
        let defaults = Self.throwaway()
        defaults.set(true, forKey: ShortcutSetup.chosenKey) // the chat, not the shortcut picker
        let preferences = Support.preferences()
        let (stream, feed) = AsyncThrowingStream<StreamOutput, Error>.makeStream()
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in stream }
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: Updater(preferences: preferences, defaults: defaults), updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        let panel = try #require(NSApp.windows.first { $0 is FloatingPanel && !before.contains(ObjectIdentifier($0)) })
        controller.layout.isShown = true
        let content = try #require(panel.contentView)

        session.draft = "Tell me everything"
        session.send()
        feed.yield(.text(Self.paragraphs(1...40)))
        /// The conversation: the one scroll view whose content is taller than it shows.
        var conversation: NSScrollView? {
            scrollViews(under: content).first { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 200 }
        }
        await settle { conversation != nil }
        let scroll = try #require(conversation, "a long answer makes the conversation scroll")
        #expect(scroll.scrollerStyle == .overlay, "whatever Show scroll bars says: a track beside the text made it re-wrap as the card shrank")
        func offset() -> CGFloat { scroll.contentView.bounds.minY }
        func height() -> CGFloat { scroll.documentView?.frame.height ?? 0 }
        /// At the answer's end: scrolled as far as following it goes, which stops at the padding under the last line.
        func isAtEnd() -> Bool { height() - scroll.contentView.bounds.height - offset() < 24 }

        // While nobody scrolls, the view stays at the answer's end as it grows.
        await settle(2) { isAtEnd() }
        #expect(isAtEnd(), "it opens on the answer's end")
        var grown = height()
        feed.yield(.text(Self.paragraphs(41...50)))
        await settle { height() > grown + 100 && isAtEnd() }
        #expect(height() > grown + 100)
        #expect(isAtEnd(), "and follows it")

        // The reader scrolls up to the start. More of the answer comes, and the view stays where it was put.
        try wheel(scroll, by: Int32(height()))
        await settle(0.5)
        #expect(offset() < 2)
        grown = height()
        feed.yield(.text(Self.paragraphs(51...60)))
        await settle { height() > grown + 100 }
        await settle(0.5)
        #expect(height() > grown + 100, "the answer grew")
        #expect(offset() < 2, "and the reader is still at its start, not pulled to its end")

        // Back at the end, the view follows again.
        try wheel(scroll, by: -Int32(height()))
        await settle(0.5)
        #expect(isAtEnd())
        grown = height()
        feed.yield(.text(Self.paragraphs(61...70)))
        await settle { height() > grown + 100 && isAtEnd() }
        #expect(height() > grown + 100)
        #expect(isAtEnd(), "at the end again, it follows again")

        feed.finish()
        await settle(0.3)
        #expect(!controller.isVisible)
    }
}
