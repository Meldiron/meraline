import AppKit
import SwiftUI

/// An answer drawn as what it changed in the text its question was about (see `TextChanges`), in the answer's
/// place: what stayed as it was in the secondary color, since here it is context for checking the changes, what
/// went struck through in red, and what came in green, each on a tint of its color so a changed comma or space
/// shows too. The gray around them is what makes three edits in a page stand out at a glance, and tells an added
/// word from its neighbors by brightness, not only hue; the line through removed words tells the two apart
/// without their colors. Plain text rather than Markdown, since the changes are to the text's own characters,
/// and code from a code block in monospace. It grows with the answers' zoom, as `MarkdownView` does.
struct ChangesView: View {
    let changes: TextChanges
    var fontSize: CGFloat = 15

    @Environment(\.answerZoom) private var zoom

    var body: some View {
        Text(Self.text(of: changes, fontSize: (changes.isCode ? fontSize - 2 : fontSize) * zoom))
            .lineSpacing((changes.isCode ? 2 : 3) * zoom)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(changes.spokenText)
    }

    static func text(of changes: TextChanges, fontSize: CGFloat) -> AttributedString {
        let font = Font.system(size: fontSize, design: changes.isCode ? .monospaced : .default)
        var text = AttributedString()
        var follows: TextChanges.Segment?
        for segment in changes.segments {
            // A thin space, unmarked, between what went and what came in its place, so the two don't run together.
            if case .removed? = follows, case .added = segment {
                var gap = AttributedString("\u{2009}")
                gap.font = font
                text += gap
            }
            follows = segment
            var run: AttributedString
            switch segment {
            case .same(let same):
                run = AttributedString(same)
                run.foregroundColor = .secondary
            case .removed(let removed):
                run = AttributedString(removed)
                run.foregroundColor = Color(nsColor: .removedText)
                run.backgroundColor = Color(nsColor: .removedTint)
                run.strikethroughStyle = .single
            case .added(let added):
                run = AttributedString(added)
                run.foregroundColor = Color(nsColor: .addedText)
                run.backgroundColor = Color(nsColor: .addedTint)
            }
            run.font = font
            text += run
        }
        return text
    }
}

/// Red and green that read well on the panel's glass: the system's own in Dark Mode, and deeper shades on light
/// glass, where the system's green is faint.
extension NSColor {
    static let removedText = NSColor(name: nil) { $0.isDark ? .systemRed : NSColor(srgbRed: 0.78, green: 0.13, blue: 0.11, alpha: 1) }
    static let addedText = NSColor(name: nil) { $0.isDark ? .systemGreen : NSColor(srgbRed: 0.1, green: 0.5, blue: 0.2, alpha: 1) }

    /// The tints behind what went and what came in `ChangesView`: stronger on dark glass, where a faint one sinks
    /// into whatever is behind the window, and a pastel on light glass, where the same tint would shout.
    static let removedTint = NSColor(name: nil) { NSColor.systemRed.withAlphaComponent($0.isDark ? 0.26 : 0.16) }
    static let addedTint = NSColor(name: nil) { NSColor.systemGreen.withAlphaComponent($0.isDark ? 0.28 : 0.2) }
}

private nonisolated extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// Under an answer that changed the text its question was about: Show What Changed, and once the changes show,
/// Show Answer to go back, with the changes in numbers beside it either way (`TextChanges.stats`). One button whose
/// label changes, in neutral glass like the tools under an answer.
struct ChangesToggle: View {
    let changes: TextChanges
    let isShowingChanges: Bool
    /// Whether ⌘D reaches this answer: it does the last one's.
    var hasShortcut = false
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Label(isShowingChanges ? "Show Answer" : "Show What Changed", systemImage: isShowingChanges ? "text.alignleft" : "plus.forwardslash.minus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(help)
            Text(changes.stats)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
    }

    private var help: String {
        let what = isShowingChanges ? "Show the answer as it came" : "Show what the answer changed in the text you asked about"
        return hasShortcut ? "\(what) (⌘D)" : what
    }
}
