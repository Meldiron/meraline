import AppKit
import SwiftUI

/// Keeps the scroll view it sits in on overlay scroll bars, whatever System Settings › Appearance › Show scroll
/// bars says. With "Always", the bar is a track beside the content that comes and goes with the content's
/// height: each time the card shrank, the conversation showed a track for half a second and its text re-wrapped
/// around it and back. Overlay bars lie over the content and take no room, as Spotlight's do, and show while
/// scrolling as before. Put in a scroll view's background; it draws nothing.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> Keeper { Keeper() }
    func updateNSView(_ view: Keeper, context: Context) { view.keep() }

    final class Keeper: NSView {
        private var observes = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            keep()
            guard !observes else { return }
            observes = true
            // AppKit puts every scroll view back on the preferred style when the setting changes.
            NotificationCenter.default.addObserver(self, selector: #selector(preferredStyleChanged), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        }

        @objc private func preferredStyleChanged(_ notification: Notification) {
            keep()
        }

        func keep() {
            guard let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay else { return }
            scrollView.scrollerStyle = .overlay
        }
    }
}
