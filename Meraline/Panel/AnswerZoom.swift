import AppKit
import SwiftUI

/// How large answers are drawn, for reading them from across the room: ⌘+ and ⌘− step through `steps`, ⌘0 goes
/// back to actual size, and a pinch on the trackpad zooms smoothly between the smallest step and the largest. Only
/// the answers' Markdown grows (its text, code, tables, and the room between them), not the rest of the window.
/// The window keeps one zoom for every chat and a torn-off note one of its own, both in memory only.
nonisolated struct AnswerZoom: Equatable, Sendable {
    static let steps: [CGFloat] = [0.85, 1, 1.15, 1.3, 1.5, 1.75, 2, 2.5, 3]
    static let actualSize = AnswerZoom(scale: 1)

    /// How much larger than their own size answers are drawn: 1.5 for 150%.
    let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = min(max(scale, Self.steps[0]), Self.steps[Self.steps.count - 1])
    }

    var isActualSize: Bool { abs(scale - 1) < Self.tolerance }

    /// "150%".
    var percent: String { "\(Int((scale * 100).rounded()))%" }

    /// Whether a step would change anything: not Zoom In at the largest step, say.
    func allows(_ step: Step) -> Bool {
        applying(step) != self
    }

    /// The next step up or down, from where a pinch left the zoom too, or actual size.
    func applying(_ step: Step) -> AnswerZoom {
        switch step {
        case .zoomIn: AnswerZoom(scale: Self.steps.first { $0 > scale + Self.tolerance } ?? scale)
        case .zoomOut: AnswerZoom(scale: Self.steps.last { $0 < scale - Self.tolerance } ?? scale)
        case .actualSize: .actualSize
        }
    }

    /// One event of a pinch: `magnification` is how much it grew since the last one, as `NSEvent.magnification`
    /// says. When the pinch ends, the zoom settles on a step it is near, so 100% stays easy to get back to, and
    /// otherwise on a whole percent.
    func pinched(by magnification: CGFloat, ending: Bool = false) -> AnswerZoom {
        let zoom = AnswerZoom(scale: scale * (1 + magnification))
        guard ending else { return zoom }
        if let step = Self.steps.first(where: { abs($0 - zoom.scale) / $0 < Self.snap }) {
            return AnswerZoom(scale: step)
        }
        return AnswerZoom(scale: (zoom.scale * 100).rounded() / 100)
    }

    private static let tolerance: CGFloat = 0.001
    /// How near a step, as a share of it, a pinch that ends there settles on it.
    private static let snap: CGFloat = 0.04

    /// Zoom In, Zoom Out, and Actual Size: in the chat's actions, and on their own in a note.
    enum Step: String, CaseIterable, Sendable {
        case zoomIn
        case zoomOut
        case actualSize

        var title: String {
            switch self {
            case .zoomIn: "Zoom In"
            case .zoomOut: "Zoom Out"
            case .actualSize: "Actual Size"
            }
        }

        var symbol: String {
            switch self {
            case .zoomIn: "plus.magnifyingglass"
            case .zoomOut: "minus.magnifyingglass"
            case .actualSize: "1.magnifyingglass"
            }
        }

        var shortcut: ActionShortcut {
            switch self {
            case .zoomIn: ActionShortcut(.plus, .command)
            case .zoomOut: ActionShortcut(.minus, .command)
            case .actualSize: .command("0")
            }
        }

        /// More words the chat's actions find it by.
        var keywords: [String] {
            switch self {
            case .zoomIn: ["bigger", "larger", "text size", "font", "magnify", "enlarge"]
            case .zoomOut: ["smaller", "text size", "font"]
            case .actualSize: ["reset", "100%", "text size", "font", "normal"]
            }
        }

        /// The step a key press asks for: ⌘+ (or ⌘=), ⌘−, or ⌘0.
        init?(keyCode: UInt16, characters: String?, modifiers: ActionShortcut.Modifiers) {
            guard let step = Self.allCases.first(where: { $0.shortcut.matches(keyCode: keyCode, characters: characters, modifiers: modifiers) }) else {
                return nil
            }
            self = step
        }
    }
}

extension EnvironmentValues {
    /// How much larger than their own size answers are drawn (see `AnswerZoom`). `MarkdownView` reads it.
    @Entry var answerZoom: CGFloat = 1
}

/// The zoom, while answers are drawn larger or smaller than their own size: a glass capsule with the percentage
/// that goes back to actual size when clicked, so zoomed answers always say why they look so and how to undo it.
struct AnswerZoomBadge: View {
    let zoom: AnswerZoom
    /// As tall as the buttons beside it.
    var height: CGFloat = 32
    let reset: () -> Void

    var body: some View {
        Button(action: reset) {
            Label(zoom.percent, systemImage: zoom.scale > 1 ? "plus.magnifyingglass" : "minus.magnifyingglass")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: zoom.scale))
                .padding(.horizontal, 10)
                .frame(height: height)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .hoverTip("Answers at \(zoom.percent). Click for Actual Size (⌘0)")
        .accessibilityLabel("Answers at \(zoom.percent)")
        .accessibilityHint("Goes back to actual size")
    }
}
