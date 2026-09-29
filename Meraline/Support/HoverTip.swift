import SwiftUI

/// A quick, glassy hover tip in place of macOS's native `.help(_:)` tooltip, which takes about a second and a half
/// to show and looks nothing like the rest of the panel. `.hoverTip("…")` shows `text` on a small glass card just
/// off the view after a short hover (`HoverTip.delay`), springs in and fades out, never takes a click, and reads
/// as an accessibility hint too. It opens above the view by default; the top row's buttons pass `edge: .bottom` so
/// it opens into the card rather than off the top of the window.
extension View {
    func hoverTip(_ text: String, edge: Edge = .top) -> some View {
        modifier(HoverTip(text: text, edge: edge))
    }
}

private struct HoverTip: ViewModifier {
    let text: String
    let edge: Edge

    /// How long the pointer rests before the tip shows, far quicker than the native tooltip.
    nonisolated static let delay = Duration.milliseconds(300)
    /// The gap between the view and the tip.
    nonisolated static let gap: CGFloat = 6

    @State private var shown = false
    @State private var waiting: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .bottom ? .bottom : .top) { tip }
            .onHover { inside in
                waiting?.cancel()
                if inside {
                    waiting = Task {
                        try? await Task.sleep(for: Self.delay)
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.7)) {
                            shown = true
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.13)) { shown = false }
                }
            }
            .onDisappear { waiting?.cancel() }
            .accessibilityHint(text)
    }

    @ViewBuilder private var tip: some View {
        if shown, !text.isEmpty {
            // Its own container so the scale and fade of the transition reach its glass, which a shared container
            // would otherwise draw past.
            GlassEffectContainer {
                HoverTipCard(text: text)
            }
            .fixedSize()
            // Lifted clear of the view, its height and width worked out from its own bounds so a line or three fit.
            .alignmentGuide(edge == .bottom ? .bottom : .top) { d in
                edge == .bottom ? d[.top] - Self.gap : d[VerticalAlignment.bottom] + Self.gap
            }
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.92, anchor: edge == .bottom ? .top : .bottom).combined(with: .opacity))
            .zIndex(1000)
        }
    }
}

/// The tip's card: a line or a few of secondary text on neutral glass, with a soft shadow so it lifts off whatever
/// is behind it.
private struct HoverTipCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 260)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}
