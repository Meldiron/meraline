import SwiftUI

/// Settings › Prompt's presets of one mode, the capsules above an empty chat in it (see `PromptPreset`): a list of
/// rows in their order, each its icon, name, and the start of its text. A row is dragged to its new place (or moved
/// with VoiceOver's actions), and Edit…, a double-click, or its menu opens it in a sheet (`PresetEditor`), where its
/// icon, name, and text change and Save keeps them. Add Preset… opens the same sheet for a new one. Deleting a
/// preset and Restore Defaults, which brings back the four Meraline starts with, both ask first.
struct PresetsSection: View {
    let preferences: Preferences
    let kind: ProviderKind
    @State private var editing: Editing?
    @State private var deleting: PromptPreset?
    @State private var isRestoring = false

    /// A preset open in the editor, and whether Save adds it to the list.
    struct Editing: Identifiable {
        var preset: PromptPreset
        var isNew: Bool
        var id: PromptPreset.ID { preset.id }
    }

    private var presets: [PromptPreset] { preferences[presets: kind] }

    var body: some View {
        Section {
            if presets.isEmpty {
                Text("No presets. Add one, or restore the four Meraline starts with.")
                    .foregroundStyle(.secondary)
            } else {
                PresetList(presets: presets, edit: edit, duplicate: duplicate, delete: { deleting = $0 }, move: move)
            }
            AddPresetRow { editing = Editing(preset: .blank(), isNew: true) }
                .sheet(item: $editing) { item in
                    PresetEditor(kind: kind, preset: item.preset, isNew: item.isNew, comesBack: isDefault(item.preset)) { preset in
                        save(preset, isNew: item.isNew)
                    } delete: {
                        delete(item.preset.id)
                    }
                }
                .confirmationDialog(
                    deleting.map(Self.deleteTitle) ?? "",
                    isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                    titleVisibility: .visible,
                    presenting: deleting
                ) { preset in
                    Button("Delete Preset", role: .destructive) { delete(preset.id) }
                } message: { preset in
                    Text(Self.deleteMessage(comesBack: isDefault(preset)))
                }
                .confirmationDialog("Restore the default \(kind.title) presets?", isPresented: $isRestoring, titleVisibility: .visible) {
                    Button("Restore Defaults", role: .destructive, action: restore)
                } message: {
                    Text("The presets go back to the four Meraline starts with: \(PromptPreset.defaults(for: kind, in: preferences.language).map(\.title).formatted(.list(type: .and))). Presets you added and changes you made go.")
                }
        } header: {
            Text("\(kind.title) Presets")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text(footer)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Restore Defaults…") { isRestoring = true }
                    .disabled(!preferences.arePresetsChanged(for: kind))
            }
        }
    }

    private var footer: String {
        switch kind {
        case .llm:
            "Above an empty chat in LLM mode. A click puts a preset’s text in the input, a Shift-click sends it, and once an answer is ready, ⌘1 to ⌘9 run the first nine on it."
        case .agent:
            "Above an empty chat in Agent mode, for work on the files you attach or on the web. A click puts a preset’s text in the input, a Shift-click sends it, and once an answer is ready, ⌘1 to ⌘9 run the first nine on it."
        case .decision:
            "Above an empty chat in Decision mode: questions about the text you add. A click puts one in the input, and a Shift-click asks it."
        }
    }

    static func deleteTitle(of preset: PromptPreset) -> String {
        preset.title.trimmed.isEmpty ? "Delete this preset?" : "Delete “\(preset.title.trimmed)”?"
    }

    static func deleteMessage(comesBack: Bool) -> String {
        comesBack
            ? "It goes from the row above an empty chat and from Actions. Restore Defaults brings it back."
            : "It goes from the row above an empty chat and from Actions. You can’t undo this."
    }

    /// Whether Restore Defaults brings a preset back: it is one Meraline starts with.
    private func isDefault(_ preset: PromptPreset) -> Bool {
        PromptPreset.defaults(for: kind, in: preferences.language).contains { $0.id == preset.id }
    }

    private func edit(_ preset: PromptPreset) {
        editing = Editing(preset: preset, isNew: false)
    }

    private func save(_ preset: PromptPreset, isNew: Bool) {
        if !isNew, let index = presets.firstIndex(where: { $0.id == preset.id }) {
            preferences[presets: kind][index] = preset
        } else {
            preferences[presets: kind].append(preset)
            Log.settings.info("\(kind.title) preset added, \(presets.count) now")
        }
    }

    private func duplicate(_ preset: PromptPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var copy = preset
        copy.id = UUID().uuidString
        copy.title = preset.title.trimmed.isEmpty ? "" : "\(preset.title.trimmed) Copy"
        preferences[presets: kind].insert(copy, at: index + 1)
        Log.settings.info("\(kind.title) preset duplicated, \(presets.count) now")
    }

    private func move(from source: Int, to destination: Int) {
        let moved = PromptPreset.moving(presets, from: source, to: destination)
        guard moved != presets else { return }
        preferences[presets: kind] = moved
    }

    private func delete(_ id: PromptPreset.ID) {
        preferences[presets: kind].removeAll { $0.id == id }
        Log.settings.info("\(kind.title) preset deleted, \(presets.count) left")
    }

    private func restore() {
        preferences[presets: kind] = PromptPreset.defaults(for: kind, in: preferences.language)
        Log.settings.info("\(kind.title) presets restored")
    }
}

extension ProviderKind {
    /// The id of the mode's section of presets in Settings › Prompt, apart from the id of its prompt's section.
    var presetsSection: String { "presets.\(rawValue)" }
}

extension PromptPreset {
    /// The list with the preset at `source` taken out and put back at `destination`, a place among the others.
    static func moving(_ presets: [PromptPreset], from source: Int, to destination: Int) -> [PromptPreset] {
        guard presets.indices.contains(source) else { return presets }
        var moved = presets
        let preset = moved.remove(at: source)
        moved.insert(preset, at: min(max(destination, 0), moved.count))
        return moved
    }
}

// MARK: The list

/// The rows of a mode's presets, one row of the form, so a dragged row can pass over the others: it follows the
/// pointer, lifted on a card of its own, while the rows it passes slide out of its way, and lands where it is let
/// go. The separators between rows step aside meanwhile.
private struct PresetList: View {
    let presets: [PromptPreset]
    let edit: (PromptPreset) -> Void
    let duplicate: (PromptPreset) -> Void
    let delete: (PromptPreset) -> Void
    let move: (_ source: Int, _ destination: Int) -> Void

    @State private var dragged: PromptPreset.ID?
    @State private var translation: CGFloat = 0
    @State private var heights: [PromptPreset.ID: CGFloat] = [:]

    private static let space = "presets"
    /// Where the separators start, past the icon, as the form's own do.
    static let separatorInset: CGFloat = PresetRow.iconSize + PresetRow.spacing

    private var rowHeights: [CGFloat] { presets.map { heights[$0.id] ?? PresetRow.iconSize + 2 * PresetRow.padding } }
    private var source: Int? { dragged.flatMap { id in presets.firstIndex { $0.id == id } } }
    private var destination: Int? {
        source.map { PresetDrag.destination(from: $0, translation: translation, heights: rowHeights) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                let isDragged = preset.id == dragged
                PresetRow(preset: preset, isLifted: isDragged) { edit(preset) }
                    .overlay(alignment: .top) {
                        Divider()
                            .padding(.leading, Self.separatorInset)
                            .opacity(index > 0 && dragged == nil ? 1 : 0)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[preset.id] = $0 }
                    .offset(y: offset(of: index, isDragged: isDragged))
                    .animation(isDragged ? nil : .snappy(duration: 0.22), value: destination)
                    .zIndex(isDragged ? 1 : 0)
                    .gesture(drag(of: preset))
                    .onTapGesture(count: 2) { edit(preset) }
                    .contextMenu {
                        Button("Edit…") { edit(preset) }
                        Button("Duplicate") { duplicate(preset) }
                        Divider()
                        Button("Delete…", role: .destructive) { delete(preset) }
                    }
                    .accessibilityActions {
                        if index > 0 {
                            Button("Move Up") { move(index, index - 1) }
                        }
                        if index < presets.count - 1 {
                            Button("Move Down") { move(index, index + 1) }
                        }
                        Button("Delete") { delete(preset) }
                    }
            }
        }
        .coordinateSpace(.named(Self.space))
        .animation(.snappy(duration: 0.22), value: dragged == nil)
    }

    /// How far a row is off its place: the dragged one by the pointer, and those between its place and where it
    /// would land by its height, out of its way.
    private func offset(of index: Int, isDragged: Bool) -> CGFloat {
        if isDragged { return translation }
        guard let source, let destination else { return 0 }
        return PresetDrag.shift(of: index, from: source, to: destination, height: rowHeights[source])
    }

    private func drag(of preset: PromptPreset) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragged == nil { dragged = preset.id }
                guard dragged == preset.id, let source else { return }
                translation = PresetDrag.clamped(value.translation.height, from: source, heights: rowHeights)
            }
            .onEnded { _ in
                let landing = source.flatMap { source in destination.map { (source, $0) } }
                withAnimation(.snappy(duration: 0.25)) {
                    if let (source, destination) = landing, source != destination { move(source, destination) }
                    dragged = nil
                    translation = 0
                }
            }
    }
}

/// Where a dragged row lands and how the others make way, worked out from the rows' heights alone.
enum PresetDrag {
    /// The place among the other rows that a row dragged from `source` by `translation` takes: past every row below
    /// whose middle its bottom edge has passed, and before every row above whose middle its top edge has passed.
    /// Edges, not its middle, so it reaches the first and last place however tall it is.
    static func destination(from source: Int, translation: CGFloat, heights: [CGFloat]) -> Int {
        guard heights.indices.contains(source) else { return source }
        let tops = heights.indices.map { heights[..<$0].reduce(0, +) }
        let top = tops[source] + translation
        let bottom = top + heights[source]
        return heights.indices.filter { index in
            let middle = tops[index] + heights[index] / 2
            return index < source ? top > middle : index > source && bottom > middle
        }.count
    }

    /// A drag that keeps the row inside the list: no higher than the top, no lower than the bottom.
    static func clamped(_ translation: CGFloat, from source: Int, heights: [CGFloat]) -> CGFloat {
        guard heights.indices.contains(source) else { return 0 }
        let top = heights[..<source].reduce(0, +)
        let bottom = heights.reduce(0, +) - top - heights[source]
        return min(max(translation, -top), bottom)
    }

    /// How far the row at `index` moves while the row at `source`, `height` tall, would land at `destination`:
    /// up by its height when it is passed on the way down, down when passed on the way up.
    static func shift(of index: Int, from source: Int, to destination: Int, height: CGFloat) -> CGFloat {
        if source < index, index <= destination { return -height }
        if destination <= index, index < source { return height }
        return 0
    }
}

/// One preset in the list: its icon on a gray tile like the panes' in the sidebar, its name, the start of its
/// text, Edit…, and the handle that says it can be dragged.
private struct PresetRow: View {
    let preset: PromptPreset
    let isLifted: Bool
    let edit: () -> Void

    static let iconSize: CGFloat = 26
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 6

    private var title: String { preset.title.trimmed }
    private var text: String { preset.text.trimmed.replacingOccurrences(of: "\n", with: " ") }

    var body: some View {
        HStack(spacing: Self.spacing) {
            SettingsIcon(symbol: preset.shownSymbol, tint: .gray, size: Self.iconSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if text.isEmpty {
                    Label("No text yet, so it stays out of the chat", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                } else {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 12)
            Button("Edit…", action: edit)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: Self.iconSize)
                .contentShape(.rect)
                .pointerStyle(isLifted ? .grabActive : .grabIdle)
                .help("Drag to change the order")
                .accessibilityHidden(true)
        }
        .padding(.vertical, Self.padding)
        .contentShape(.rect)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(isLifted ? 0.18 : 0), radius: 8, y: 3)
                .padding(.horizontal, -8)
                .opacity(isLifted ? 1 : 0)
        }
        .scaleEffect(isLifted ? 1.02 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title.isEmpty ? "Untitled preset" : title)
    }
}

/// The last row of the list, lined up with the presets' icons.
private struct AddPresetRow: View {
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: PresetRow.spacing) {
                RoundedRectangle(cornerRadius: PresetRow.iconSize * 0.26, style: .continuous)
                    .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: PresetRow.iconSize, height: PresetRow.iconSize)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                Text("Add Preset…")
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: The editor

/// A preset in a sheet of its own: its icon, which a click changes (`SymbolPicker`), its name, and its text. Save
/// keeps the changes, or Add Preset for a new one, which asks for a name and text first; Cancel and Esc leave the
/// preset as it was. Delete Preset… asks before it deletes.
struct PresetEditor: View {
    let kind: ProviderKind
    let isNew: Bool
    /// Whether Restore Defaults would bring the preset back, which the question before deleting it says.
    let comesBack: Bool
    let save: (PromptPreset) -> Void
    let delete: () -> Void

    @State private var preset: PromptPreset
    @State private var isChoosingIcon: Bool
    /// What the icons are searched for as they open, for the showcase's picture of them.
    private let iconQuery: String
    @State private var isDeleting = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        kind: ProviderKind, preset: PromptPreset, isNew: Bool, comesBack: Bool, choosingIcon: Bool = false, iconQuery: String = "",
        save: @escaping (PromptPreset) -> Void, delete: @escaping () -> Void
    ) {
        self.kind = kind
        self.isNew = isNew
        self.comesBack = comesBack
        self.save = save
        self.delete = delete
        // The sheet edits a copy of its own from the moment it opens; nothing outside it changes the preset meanwhile.
        _preset = State(initialValue: preset)
        _isChoosingIcon = State(initialValue: choosingIcon)
        self.iconQuery = iconQuery
    }

    private var canSave: Bool { !preset.title.trimmed.isEmpty && !preset.text.trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        IconWell(symbol: preset.shownSymbol) { isChoosingIcon = true }
                            .popover(isPresented: $isChoosingIcon, arrowEdge: .bottom) {
                                SymbolPicker(symbol: $preset.symbol, query: iconQuery) { isChoosingIcon = false }
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("Name", text: $preset.title, prompt: Text("Name"))
                                .textFieldStyle(.plain)
                                .font(.title3.weight(.semibold))
                                .labelsHidden()
                                .focused($isNameFocused)
                            Text("Shown with its icon above an empty chat")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    // No scroller, which a Mac with a mouse would draw as a track down the side of every short text.
                    TextEditor(text: $preset.text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .frame(height: 104)
                        .labelsHidden()
                        .overlay(alignment: .topLeading) {
                            if preset.text.isEmpty {
                                Text(placeholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(kind == .decision ? "Question" : "Prompt")
                } header: {
                    Text(kind == .decision ? "Question" : "Prompt")
                } footer: {
                    Text(footer)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                if !isNew {
                    Button("Delete Preset…", role: .destructive) { isDeleting = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Preset" : "Save") {
                    save(preset)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 480, height: 400)
        .onAppear { isNameFocused = isNew }
        .confirmationDialog(PresetsSection.deleteTitle(of: preset), isPresented: $isDeleting, titleVisibility: .visible) {
            Button("Delete Preset", role: .destructive) {
                delete()
                dismiss()
            }
        } message: {
            Text(PresetsSection.deleteMessage(comesBack: comesBack))
        }
    }

    private var placeholder: String {
        switch kind {
        case .llm: "Fix the grammar of this text, and reply with the corrected text only."
        case .agent: "Look through the files attached for bugs, and list each with how to fix it."
        case .decision: "Is this urgent?"
        }
    }

    private var footer: String {
        switch kind {
        case .llm, .agent:
            "A click on the preset puts this in the input, ahead of anything typed there. End it as a sentence: the text it works on comes on a card of its own."
        case .decision:
            "Yes or No, unless the question names its answers after the question mark, with / between them, “Friendly / Neutral / Angry”, or < for levels in order, “Low < Medium < High”."
        }
    }
}

/// The preset's icon, large, as the button that opens the icons to choose from, with a pencil on its corner that
/// says so.
private struct IconWell: View {
    let symbol: String
    let choose: () -> Void
    @State private var isHovering = false

    private static let size: CGFloat = 52

    var body: some View {
        Button(action: choose) {
            SettingsIcon(symbol: symbol, tint: .gray, size: Self.size)
                .brightness(isHovering ? 0.06 : 0)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.background, in: .circle)
                        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                        .offset(x: 5, y: 5)
                }
                .contentShape(.rect(cornerRadius: Self.size * 0.26))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Choose an icon")
        .accessibilityLabel("Icon")
        .accessibilityValue(symbol)
        .accessibilityHint("Opens the icons to choose from")
    }
}
