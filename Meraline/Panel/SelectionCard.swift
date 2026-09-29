import AppKit
import KeyboardShortcuts
import SwiftUI

/// The text selected in another app, between the input and the row under it, going along with the next
/// question. Neutral glass like the panel's other cards: the app's icon, its name, and how long the text is,
/// then the text itself as a quote of up to three lines, which the chevron opens in full when they cut it
/// short. The cross, or ⌫ in an empty input, leaves the selection out.
struct SelectionCard: View {
    let selection: SelectedText
    let remove: () -> Void

    @State private var isExpanded = false
    @State private var isCut = false
    @State private var textHeight: CGFloat = 0

    /// The three lines leave some of the text out, or the card is open in full and can close again.
    private var canExpand: Bool { isExpanded || isCut }

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
            Text(selection.sourceLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("· \(selection.lengthLabel)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            if canExpand {
                CardButton(symbol: "chevron.down", label: isExpanded ? "Show less" : "Show all", turn: .degrees(isExpanded ? 180 : 0)) {
                    isExpanded.toggle()
                }
                .hoverTip(isExpanded ? "Show less" : "Show all of it")
            }
            CardButton(symbol: "xmark", label: "Leave out the selected text", action: remove)
                .hoverTip("Leave it out (⌫ in an empty input)")
        }
        .lineLimit(1)
    }

    private var quote: some View {
        HStack(alignment: .top, spacing: 10) {
            QuoteBar()
            if isExpanded {
                ScrollView {
                    QuoteText(selection.text, size: 13, lineSpacing: 2)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }
                }
                .frame(height: min(textHeight, 200))
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            } else {
                QuoteText(selection.text, lines: 3, size: 13, lineSpacing: 2, isCut: $isCut)
            }
        }
        .foregroundStyle(.primary.opacity(0.85))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The selection a question went with, above the question in the conversation: the app it came from and how
/// long the text is, then two quiet lines of the text. When the two lines cut it short, a chevron joins the
/// header, and the header opens all of the text in place, in the conversation's own scroll, and folds it back.
struct SelectionQuote: View {
    let selection: SelectedText

    @State private var isExpanded = false
    @State private var isCut = false

    private var canExpand: Bool { isExpanded || isCut }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            QuoteBar()
            VStack(alignment: .leading, spacing: 3) {
                if canExpand {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        header.contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .hoverTip(isExpanded ? "Show less" : "Show all of it")
                    .accessibilityLabel("\(selection.sourceLabel), \(selection.lengthLabel)")
                    .accessibilityHint(isExpanded ? "Shows less of the text" : "Shows all of the text")
                } else {
                    header
                }
                QuoteText(selection.text, lines: 2, isOpen: isExpanded, size: 12, isCut: $isCut)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.smooth(duration: 0.25), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Asked about text\(selection.appName.map { " from \($0)" } ?? "")")
    }

    private var header: some View {
        HStack(spacing: 5) {
            AppIcon(selection: selection, size: 13)
            Text(selection.sourceLabel)
                .font(.system(size: 11, weight: .medium))
            Text("· \(selection.lengthLabel)")
                .font(.system(size: 11))
            if canExpand {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.tertiary)
        .lineLimit(1)
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
                .hoverTip("Hide this hint. Settings › Permissions can allow access later.")
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var shortcut: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "the shortcut"
    }
}

/// A quote's text, cut to `lines` of it until `isOpen` (all of it when `lines` is nil), that knows whether the
/// cut leaves anything out: behind the text, hidden, the same text is laid out twice more, cut the same way and
/// in full, and `isCut` says whether the full one is taller. So a chevron shows only when there is more to see,
/// whatever the width and the font, and a text of exactly three lines gets none. The copies keep measuring
/// while the text is open, so the chevron stays to close it. They never draw, take clicks, or count for
/// accessibility, and the visible text stays selectable.
private struct QuoteText: View {
    let text: String
    let lines: Int?
    var isOpen = false
    let size: CGFloat
    var lineSpacing: CGFloat = 0
    var isCut: Binding<Bool> = .constant(false)

    @State private var cutHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    init(_ text: String, lines: Int? = nil, isOpen: Bool = false, size: CGFloat, lineSpacing: CGFloat = 0, isCut: Binding<Bool> = .constant(false)) {
        self.text = text
        self.lines = lines
        self.isOpen = isOpen
        self.size = size
        self.lineSpacing = lineSpacing
        self.isCut = isCut
    }

    var body: some View {
        styled(Text(text))
            .lineLimit(isOpen ? nil : lines)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                if let lines {
                    ZStack(alignment: .topLeading) {
                        styled(Text(text))
                            .lineLimit(lines)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { cutHeight = $0 }
                        styled(Text(text))
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: fullHeight > cutHeight + 0.5, initial: true) { isCut.wrappedValue = $1 }
    }

    private func styled(_ text: Text) -> some View {
        text
            .font(.system(size: size))
            .lineSpacing(lineSpacing)
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
struct CardButton: View {
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
                Image(systemName: selection.isFromClipboard ? "clipboard" : selection.isTyped ? "keyboard" : "text.quote")
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
