import AppKit
import KeyboardShortcuts
import SwiftUI

/// The text selected in another app, between the input and the row under it, going along with the next
/// question. Neutral glass like the panel's other cards: the app's icon, its name, and how long the text is,
/// then the text itself as a quote of up to three lines, which the chevron opens in full. The cross, or ⌫ in
/// an empty input, leaves the selection out.
struct SelectionCard: View {
    let selection: SelectedText
    let remove: () -> Void

    @State private var isExpanded = false
    @State private var textHeight: CGFloat = 0

    /// Past about three lines of the card's width, or three line breaks, the quote is cut short.
    private var isLong: Bool {
        selection.text.count > 260 || selection.text.filter(\.isNewline).count >= 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            quote
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(.smooth(duration: 0.25), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected text\(selection.appName.map { " from \($0)" } ?? "")")
    }

    private var header: some View {
        HStack(spacing: 6) {
            AppIcon(selection: selection, size: 16)
            Text(selection.appName ?? "Selected text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(length)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            if isLong {
                CardButton(symbol: "chevron.down", label: isExpanded ? "Show less" : "Show all", turn: .degrees(isExpanded ? 180 : 0)) {
                    isExpanded.toggle()
                }
                .help(isExpanded ? "Show less" : "Show all of it")
            }
            CardButton(symbol: "xmark", label: "Leave out the selected text", action: remove)
                .help("Leave it out (⌫ in an empty input)")
        }
        .lineLimit(1)
    }

    private var length: String {
        if selection.isShortened { return "· first \(SelectedText.limit.formatted()) characters" }
        let words = selection.wordCount
        return "· \(words.formatted()) \(words == 1 ? "word" : "words")"
    }

    private var quote: some View {
        HStack(alignment: .top, spacing: 10) {
            QuoteBar()
            if isExpanded {
                ScrollView {
                    quoteText
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }
                }
                .frame(height: min(textHeight, 200))
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            } else {
                quoteText.lineLimit(3)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var quoteText: some View {
        Text(selection.text)
            .font(.system(size: 13))
            .lineSpacing(2)
            .foregroundStyle(.primary.opacity(0.85))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The selection a question went with, above the question in the conversation: the app it came from, then
/// two quiet lines of the text.
struct SelectionQuote: View {
    let selection: SelectedText

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            QuoteBar()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    AppIcon(selection: selection, size: 13)
                    Text(selection.appName ?? "Selected text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Text(selection.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Asked about text\(selection.appName.map { " from \($0)" } ?? ""): \(selection.excerpt)")
    }
}

/// Until Meraline may read the selection: what the shortcut can bring, and the way to allow it. Glass like
/// the setup row, with the faint pink of the panel's buttons on Allow Access.
struct SelectionHintRow: View {
    let allow: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.quote")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask about what you select")
                    .font(.system(size: 13, weight: .semibold))
                Text("Select text in any app and press \(shortcut), then add it with the cursor button above the window. Files selected in Finder come along by themselves. Meraline needs Accessibility access to read the selection.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Allow Access…", action: allow)
                .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
            CardButton(symbol: "xmark", label: "Hide this hint", action: dismiss)
                .help("Hide this hint. Settings › General can allow access later.")
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var shortcut: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "the shortcut"
    }
}

/// The thin rule down the side of a quote.
private struct QuoteBar: View {
    var body: some View {
        Capsule()
            .fill(.primary.opacity(0.16))
            .frame(width: 3)
            .accessibilityHidden(true)
    }
}

/// A small glass circle with a symbol, for the cards' own controls. `turn` rotates the symbol alone: glass in
/// the panel's glass container can't be rotated, and a rotated circle swells into a disc beside its place
/// while it turns.
private struct CardButton: View {
    let symbol: String
    let label: String
    var turn: Angle = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(turn)
                .frame(width: 20, height: 20)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The Finder icon of the app a selection came from, a clipboard for copied text, or a quote mark when the
/// app is unknown.
private struct AppIcon: View {
    let selection: SelectedText
    let size: CGFloat

    var body: some View {
        Group {
            if let url = selection.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: selection.isFromClipboard ? "clipboard" : "text.quote")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.15)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
