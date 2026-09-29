import AppKit
import SwiftUI

/// A panel of actions in the manner of Raycast's: a heading, rows in sections with an icon, a title, and the
/// shortcut as keycaps, and a search field at the bottom that filters them. The arrows move the selection,
/// Return runs it, and Esc closes the panel. An action that can't be undone asks first, in the panel itself:
/// a sheet or an alert would take the keyboard from the window, which closes when it loses it.
struct ActionPanel: View {
    let menu: ActionMenu
    let request: ActionPanelRequest
    let run: (PanelAction) -> Void
    let confirm: (PanelAction) -> Void
    /// Esc, or Cancel in a confirmation: back to the list, or the panel closes.
    let cancel: () -> Void

    @State private var query = ""
    @State private var selection: PanelAction.ID?
    /// In a confirmation, whether Return goes ahead rather than cancels.
    @State private var confirmsOnReturn = true

    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 18
    private static let rowHeight: CGFloat = 34
    private static let tallRowHeight: CGFloat = 42
    private static let headerHeight: CGFloat = 34
    private static let dividerHeight: CGFloat = 11
    private static let searchHeight: CGFloat = 45
    private static let confirmationHeight: CGFloat = 160
    private static let maximumRowsHeight: CGFloat = 330

    private var sections: [ActionSection] { menu.filtered(by: query) }
    private var visible: [PanelAction] { sections.flatMap(\.actions) }

    private var confirming: PanelAction? {
        request.confirming.flatMap { id in menu.actions.first { $0.id == id } }
    }

    /// The selected row: the one the arrows or the pointer picked, or else the first.
    private var selected: PanelAction.ID? {
        if let selection, visible.contains(where: { $0.id == selection }) { return selection }
        return visible.first?.id
    }

    /// How tall the rows are: every row and divider has a fixed height, so the list needs no measuring and has
    /// its height from its first frame.
    static func rowsHeight(of sections: [ActionSection]) -> CGFloat {
        let rows = sections.flatMap(\.actions).reduce(0) { $0 + ($1.subtitle == nil ? rowHeight : tallRowHeight) }
        return rows + CGFloat(max(0, sections.count - 1)) * dividerHeight + 6
    }

    /// About how tall the panel is with nothing typed, to choose whether it opens above or below its button.
    static func estimatedHeight(of menu: ActionMenu, confirming: Bool) -> CGFloat {
        if confirming { return confirmationHeight }
        let sections = menu.filtered(by: "")
        let rows = sections.isEmpty ? 44 : min(rowsHeight(of: sections), maximumRowsHeight)
        return headerHeight + 2 + rows + searchHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            if let action = confirming, let confirmation = action.confirmation {
                confirmationView(for: action, confirmation)
                    .transition(.opacity)
            } else {
                list
                    .transition(.opacity)
            }
            searchBar
        }
        .frame(width: Self.width)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .animation(.smooth(duration: 0.18), value: request.confirming)
        .onChange(of: query) { selection = nil }
        .onChange(of: request.confirming) { confirmsOnReturn = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(menu.title)
    }

    // MARK: The list

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(menu.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .frame(height: Self.headerHeight, alignment: .bottomLeading)
                .padding(.bottom, 2)
            if visible.isEmpty {
                Text(query.trimmed.isEmpty ? menu.emptyText : "No matching actions")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                rows
            }
        }
    }

    /// The rows, scrolling only when there are too many to show at once.
    private var rows: some View {
        let height = Self.rowsHeight(of: sections)
        return ScrollViewReader { proxy in
            ScrollView {
                rowStack
            }
            .scrollIndicators(.never)
            .scrollDisabled(height <= Self.maximumRowsHeight)
            .frame(height: min(height, Self.maximumRowsHeight))
            .onChange(of: selection) {
                if let selection { proxy.scrollTo(selection) }
            }
        }
    }

    private var rowStack: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                VStack(spacing: 0) {
                    if section.id != sections.first?.id {
                        Divider().padding(.vertical, 5)
                    }
                    ForEach(section.actions) { action in
                        row(action, isPrimary: menu.marksPrimary && query.trimmed.isEmpty && action.id == menu.primary?.id)
                            .id(action.id)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func row(_ action: PanelAction, isPrimary: Bool) -> some View {
        let isSelected = action.id == selected
        return Button { run(action) } label: {
            HStack(spacing: 10) {
                icon(action.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = action.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if let detail = action.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if action.isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.meralinePink)
                        .accessibilityLabel("On")
                }
                if isPrimary {
                    KeyCaps(keys: ActionShortcut.returnKey.keycaps)
                } else if let shortcut = action.shortcut {
                    KeyCaps(keys: shortcut.keycaps)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: action.subtitle == nil ? Self.rowHeight : Self.tallRowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.primary.opacity(0.08))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { inside in
            if inside { selection = action.id }
        }
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func icon(_ icon: PanelAction.Icon) -> some View {
        switch icon {
        case .symbol(let name): Image(systemName: name)
        case .image(let image): image
        }
    }

    // MARK: Confirmation

    private func confirmationView(for action: PanelAction, _ confirmation: ActionConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                icon(action.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill((action.isDestructive ? Color.red : Color.primary).opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(confirmation.title)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(confirmation.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Divider()
            VStack(spacing: 0) {
                confirmationRow(confirmation.button, keys: ActionShortcut.returnKey.keycaps, isDestructive: action.isDestructive, isSelected: confirmsOnReturn) {
                    confirm(action)
                }
                .onHover { if $0 { confirmsOnReturn = true } }
                confirmationRow("Cancel", keys: ActionShortcut.escape.keycaps, isDestructive: false, isSelected: !confirmsOnReturn, action: cancel)
                    .onHover { if $0 { confirmsOnReturn = false } }
            }
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(confirmation.title)
    }

    private func confirmationRow(_ title: String, keys: [String], isDestructive: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                Spacer()
                KeyCaps(keys: keys)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.primary.opacity(0.08))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: Search

    /// The search field. It stays while a confirmation shows, only hidden, so the keyboard stays with it and
    /// Return and Esc answer the confirmation.
    private var searchBar: some View {
        let isHidden = confirming != nil
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                ActionSearchField(text: $query, prompt: menu.searchPrompt, onMove: move, onSubmit: submit, onCancel: cancel)
                    .frame(height: 20)
            }
            .padding(.horizontal, 16)
            .frame(height: Self.searchHeight - 1)
        }
        .frame(height: isHidden ? 0 : nil, alignment: .top)
        .opacity(isHidden ? 0 : 1)
        .clipped()
        .accessibilityHidden(isHidden)
    }

    private func move(by step: Int) {
        if confirming != nil {
            confirmsOnReturn.toggle()
            return
        }
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selected } ?? 0
        let next = (index + step + visible.count) % visible.count
        selection = visible[next].id
    }

    private func submit() {
        if let action = confirming {
            if confirmsOnReturn { confirm(action) } else { cancel() }
        } else if let action = visible.first(where: { $0.id == selected }) {
            run(action)
        }
    }
}

/// Keys as small outlined caps, one per key: ⇧ ⌘ C.
struct KeyCaps: View {
    let keys: [String]
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: size * (key.count > 1 ? 0.5 : 0.56), weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .frame(minWidth: size, minHeight: size)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.45), lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

/// The footer's actions, after Raycast's: the primary action with its shortcut, then Actions ⌘K for the
/// rest. After a copy, the primary action says Copied for a moment.
struct ActionBar: View {
    let primary: PanelAction?
    let isOpen: Bool
    let copyNotice: Int
    let runPrimary: () -> Void
    let openActions: () -> Void

    @State private var hovered: String?
    @State private var showsCopied = false
    @State private var copiedTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 2) {
            if let primary {
                segment(id: "primary", action: runPrimary) {
                    if showsCopied {
                        Label("Copied", systemImage: "checkmark")
                            .foregroundStyle(.primary)
                            .transition(.blurReplace)
                    } else {
                        Text(primary.title)
                            .foregroundStyle(.primary)
                            .transition(.blurReplace)
                        if let shortcut = primary.shortcut {
                            KeyCaps(keys: shortcut.keycaps, size: 18)
                        }
                    }
                }
                .help(primary.shortcut.map { "\(primary.title) (\($0.text))" } ?? primary.title)
            }
            segment(id: "actions", action: openActions) {
                Text("Actions")
                    .foregroundStyle(.secondary)
                KeyCaps(keys: ["⌘", "K"], size: 18)
            }
            .help("More actions for this chat (⌘K)")
            .accessibilityLabel("Actions")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.smooth(duration: 0.2), value: showsCopied)
        .onChange(of: copyNotice) { sayCopied() }
    }

    private func segment<Label: View>(id: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        let isLit = hovered == id || (id == "actions" && isOpen)
        return Button(action: action) {
            HStack(spacing: 6) { label() }
                .padding(.leading, 11)
                .padding(.trailing, 5)
                .frame(height: 26)
                .background {
                    if isLit { Capsule().fill(.primary.opacity(0.08)) }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = id } else if hovered == id { hovered = nil }
        }
    }

    private func sayCopied() {
        copiedTask?.cancel()
        showsCopied = true
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            showsCopied = false
        }
    }
}

/// Where each control that opens a panel of actions sits, so the panel can open beside it.
nonisolated struct ActionPanelAnchors: PreferenceKey {
    static var defaultValue: [ActionPanelKind: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [ActionPanelKind: Anchor<CGRect>], nextValue: () -> [ActionPanelKind: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks the control that opens a panel of actions, which opens beside it.
    func actionPanelAnchor(_ kind: ActionPanelKind) -> some View {
        anchorPreference(key: ActionPanelAnchors.self, value: .bounds) { [kind: $0] }
    }
}

/// Where an open panel of actions reaches in the window, top and bottom.
struct ActionPanelSpan: Equatable {
    let top: CGFloat
    let bottom: CGFloat
}

/// Shows the open panel of actions over the window, beside the control that opened it. The chat's and the
/// clock's open up and to the left, ending where their button ends; when the panel reaches past the card's
/// top, the window makes room above the card, raising its own top so the card stays where it is. Only when the
/// screen has no room for that do they open below instead. The sparkle's opens down and to the right. A click
/// anywhere else in the window closes the panel, as it would a menu. `report` tells the window where the panel
/// reaches, so it can make room for all of it.
struct ActionPanelHost: View {
    let anchors: [ActionPanelKind: Anchor<CGRect>]
    let context: PanelContext
    /// The room the window has made above the card, which the anchors already include.
    let roomAbove: CGFloat
    let report: (ActionPanelSpan?) -> Void

    /// The space kept between a panel and the window's edge.
    static let inset: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if context.layout.actionPanel != nil {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { context.layout.closeActionPanel() }
                        .accessibilityHidden(true)
                }
                if let request = context.layout.actionPanel, let anchor = anchors[request.kind], let menu = context.menu(for: request.kind) {
                    PlacedActionPanel(
                        menu: menu,
                        request: request,
                        button: proxy[anchor],
                        bounds: proxy.size,
                        roomAbove: roomAbove,
                        context: context,
                        report: report
                    )
                    .id(request.kind)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: request.kind == .providers ? .topLeading : .bottomTrailing)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .animation(.snappy(duration: 0.22), value: context.layout.actionPanel?.kind)
    }
}

/// A panel of actions at its place beside its button, laid out with padding from the host's corner so its
/// frame is where it shows. The direction is chosen once, when it opens, from an estimate of the whole list,
/// so it doesn't jump across its button while a search shrinks it.
private struct PlacedActionPanel: View {
    let menu: ActionMenu
    let request: ActionPanelRequest
    let button: CGRect
    let bounds: CGSize
    let roomAbove: CGFloat
    let context: PanelContext
    let report: (ActionPanelSpan?) -> Void

    @State private var height: CGFloat?
    @State private var opensUpward: Bool?

    private static let gap: CGFloat = 8

    var body: some View {
        let estimate = ActionPanel.estimatedHeight(of: menu, confirming: request.confirming != nil)
        let height = height ?? estimate
        let upward = opensUpward ?? canOpenUpward(estimate)
        let inset = ActionPanelHost.inset
        let x = request.kind == .providers ? button.minX - 6 : button.maxX - ActionPanel.width
        // Above the window's top for as long as it takes the window to make room there.
        let y = upward ? button.minY - Self.gap - height : max(button.maxY + Self.gap, inset)
        let span = ActionPanelSpan(top: y, bottom: y + height)
        ActionPanel(
            menu: menu,
            request: request,
            run: { context.run($0, in: request.kind) },
            confirm: context.confirm,
            cancel: context.layout.cancelActionPanel
        )
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
            if opensUpward == nil { opensUpward = upward }
            self.height = measured
        }
        // The button moves when the chat above it grows, and the panel with it.
        .onChange(of: span, initial: true) { report(span) }
        .onDisappear { report(nil) }
        .padding(.leading, min(max(x, inset), bounds.width - inset - ActionPanel.width))
        .padding(.top, max(y, 0))
        .offset(y: min(y, 0))
    }

    /// The chat's and the clock's panels open upward unless the window can't rise far enough on the screen
    /// to make the room they need above the card. The sparkle's always opens downward.
    private func canOpenUpward(_ height: CGFloat) -> Bool {
        guard request.kind != .providers else { return false }
        let topWithoutRoom = button.minY - roomAbove - Self.gap - height
        let needed = max(0, ActionPanelHost.inset - topWithoutRoom)
        return needed <= context.layout.roomOnScreenAbove
    }
}

/// The search field of an action panel: plain text in AppKit, because a SwiftUI field keeps the arrows,
/// Return, and Esc to itself. It takes the keyboard as soon as it is in the window.
struct ActionSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchTextField {
        let field = SearchTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderString = prompt
        field.stringValue = text
        field.setAccessibilityLabel(prompt)
        return field
    }

    func updateNSView(_ field: SearchTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != prompt { field.placeholderString = prompt }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ActionSearchField

        init(_ parent: ActionSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): break
            default: return false
            }
            return true
        }
    }
}

/// A text field that takes the keyboard when it joins a window, with the panel's pink cursor.
final class SearchTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            (self.currentEditor() as? NSTextView)?.insertionPointColor = NSColor(named: "Pink") ?? .controlAccentColor
        }
    }
}
