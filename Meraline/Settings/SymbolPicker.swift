import AppKit
import SwiftUI

/// The icons a preset can take, in a popover from its editor (`PresetEditor`): a search field over every SF Symbol
/// this Mac has (`SymbolCatalog`), found by name, Apple's keywords, and everyday words, and while it is empty,
/// Suggested icons first and then Apple's categories to browse. A click takes an icon; Return takes the first one
/// found, which is ringed. The name of the icon under the pointer shows at the bottom.
struct SymbolPicker: View {
    @Binding var symbol: String
    let done: () -> Void
    @State private var query: String
    @State private var found: [String] = []
    @State private var hovered: String?

    init(symbol: Binding<String>, query: String = "", done: @escaping () -> Void) {
        _symbol = symbol
        _query = State(initialValue: query)
        self.done = done
    }

    private var catalog: SymbolCatalog { .shared }
    private var isSearching: Bool { !query.trimmed.isEmpty }

    static let cell: CGFloat = 36
    static let columns = 9
    static let spacing: CGFloat = 4
    private static let padding: CGFloat = 12
    static var width: CGFloat { CGFloat(columns) * cell + CGFloat(columns - 1) * spacing + 2 * padding }

    var body: some View {
        VStack(spacing: 0) {
            SymbolSearchField(text: $query, prompt: "Search icons, such as mail or idea", submit: chooseFirst)
                .padding(Self.padding)
            Divider()
            ScrollView {
                if isSearching {
                    results
                } else {
                    browse
                }
            }
            .frame(height: 312)
            Divider()
            footer
        }
        .frame(width: Self.width)
        .onChange(of: query, initial: true) {
            found = catalog.search(query)
        }
    }

    private var grid: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.spacing), count: Self.columns)
    }

    @ViewBuilder
    private var results: some View {
        if found.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No icons for “\(query.trimmed)”")
                    .font(.headline)
                Text("Try another word for it, such as mail, star, warning, or idea, or clear the search to browse.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            LazyVGrid(columns: grid, spacing: Self.spacing) {
                ForEach(Array(found.enumerated()), id: \.element) { index, name in
                    cell(name, isTopHit: index == 0)
                }
            }
            .padding(Self.padding)
        }
    }

    /// The Suggested icons, the preset's own first when it is none of them.
    private var suggested: [String] {
        let suggested = PromptPreset.symbols.map(catalog.current)
        let current = catalog.current(symbol)
        return suggested.contains(current) || !PromptPreset.exists(current) ? suggested : [current] + suggested
    }

    private var browse: some View {
        LazyVGrid(columns: grid, spacing: Self.spacing) {
            Section {
                ForEach(suggested, id: \.self) { cell($0) }
            } header: {
                header("Suggested")
            }
            ForEach(catalog.categories) { category in
                Section {
                    ForEach(category.names, id: \.self) { cell($0) }
                } header: {
                    header(category.title)
                }
            }
        }
        .padding([.horizontal, .bottom], Self.padding)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func cell(_ name: String, isTopHit: Bool = false) -> some View {
        let isChosen = name == catalog.current(symbol)
        let isHovered = name == hovered
        return Button {
            choose(name)
        } label: {
            Image(systemName: name)
                .font(.system(size: 16))
                .foregroundStyle(isChosen ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.primary))
                .frame(width: Self.cell, height: Self.cell)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isChosen ? AnyShapeStyle(Color.meralinePink.opacity(0.16)) : isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                }
                .overlay {
                    if isTopHit, !isChosen {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
                    }
                }
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isInside in
            if isInside {
                hovered = name
            } else if hovered == name {
                hovered = nil
            }
        }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: PromptPreset.exists(hovered ?? symbol) ? hovered ?? symbol : PromptPreset.fallbackSymbol)
                .font(.system(size: 12))
                .frame(width: 16)
            Text(hovered ?? catalog.current(symbol))
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if isSearching {
                Text(found.count == 1 ? "1 icon" : "\(found.count.formatted()) icons")
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Self.padding)
        .padding(.vertical, 8)
    }

    private func chooseFirst() {
        if let first = found.first { choose(first) }
    }

    private func choose(_ name: String) {
        symbol = name
        done()
    }
}

/// AppKit's search field, for its look, its clear button, and Esc, which clears it before it closes the popover.
/// It takes the keyboard as soon as it is in a window, so typing searches at once.
private struct SymbolSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let submit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusingSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SymbolSearchField

        init(parent: SymbolSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.submit()
            return true
        }
    }

    private final class FocusingSearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}
