import SwiftUI

/// Settings › Prompt's presets of one mode, the capsules above an empty chat in it (see `PromptPreset`). Each
/// folds under its icon and name, and opens on its icon, name, and text, with buttons to move it along the row or
/// delete it. Add Preset makes one more, and Restore Defaults brings back the four Meraline starts with.
struct PresetsSection: View {
    let preferences: Preferences
    let kind: ProviderKind
    /// The presets unfolded, a new one among them.
    @State private var expanded: Set<PromptPreset.ID> = []

    var body: some View {
        Section {
            let presets = preferences[presets: kind]
            ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                PresetRow(
                    preset: binding(for: preset.id),
                    isExpanded: expansion(of: preset.id),
                    canMoveUp: index > 0,
                    canMoveDown: index < presets.count - 1
                ) { offset in
                    move(preset.id, by: offset)
                } delete: {
                    delete(preset.id)
                }
            }
            Button("Add Preset", systemImage: "plus", action: add)
        } header: {
            Text("\(kind.title) Presets")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text(footer)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Restore Defaults") {
                    preferences[presets: kind] = PromptPreset.defaults(for: kind, in: preferences.language)
                    Log.settings.info("\(kind.title) presets restored")
                }
                .disabled(!preferences.arePresetsChanged(for: kind))
            }
        }
    }

    private var footer: String {
        switch kind {
        case .llm:
            "They wait above an empty chat in LLM mode, beside the gear. A click puts a preset’s text in the input, ahead of anything you typed, and a Shift-click sends it at once. They’re for a chat’s first question, so they go once it starts. Once an answer is ready, Actions (⌘K) runs them on it, and ⌘1 to ⌘9 run the first nine."
        case .agent:
            "They wait above an empty chat in Agent mode, beside the gear, for work on the files you attach or on the web. A click puts a preset’s text in the input, ahead of anything you typed, and a Shift-click sends it at once. Once an answer is ready, Actions (⌘K) runs them on it, and ⌘1 to ⌘9 run the first nine."
        case .decision:
            "They wait above an empty chat in Decision mode, beside the gear: questions for Jev about the text you add. A click puts one in the input, and a Shift-click asks it at once. A preset can name its answers after the question, with / between them, or < for levels in order, as Tone and Priority do."
        }
    }

    /// A preset by its id rather than its place, so deleting one never leaves a field writing to a place that is gone.
    private func binding(for id: PromptPreset.ID) -> Binding<PromptPreset> {
        Binding(
            get: { preferences[presets: kind].first { $0.id == id } ?? PromptPreset(id: id, title: "", symbol: PromptPreset.fallbackSymbol, text: "") },
            set: { preset in
                guard let index = preferences[presets: kind].firstIndex(where: { $0.id == id }) else { return }
                preferences[presets: kind][index] = preset
            }
        )
    }

    private func expansion(of id: PromptPreset.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func add() {
        let preset = PromptPreset.blank()
        preferences[presets: kind].append(preset)
        expanded.insert(preset.id)
        Log.settings.info("Preset added, \(preferences[presets: kind].count) now")
    }

    private func move(_ id: PromptPreset.ID, by offset: Int) {
        var presets = preferences[presets: kind]
        guard let index = presets.firstIndex(where: { $0.id == id }), presets.indices.contains(index + offset) else { return }
        presets.swapAt(index, index + offset)
        preferences[presets: kind] = presets
    }

    private func delete(_ id: PromptPreset.ID) {
        preferences[presets: kind].removeAll { $0.id == id }
        expanded.remove(id)
        Log.settings.info("Preset deleted, \(preferences[presets: kind].count) left")
    }
}

/// One preset, folded under its icon and name.
private struct PresetRow: View {
    @Binding var preset: PromptPreset
    @Binding var isExpanded: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (_ offset: Int) -> Void
    let delete: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LabeledContent("Icon") {
                SymbolPicker(symbol: $preset.symbol)
            }
            TextField("Name", text: $preset.title, prompt: Text("Shown beside the icon"))
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $preset.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .labelsHidden()
                if preset.text.trimmed.isEmpty {
                    Text("Write what the preset puts in the input. Until then it stays out of the row above the chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Move Left", systemImage: "arrow.left") { move(-1) }
                    .disabled(!canMoveUp)
                Button("Move Right", systemImage: "arrow.right") { move(1) }
                    .disabled(!canMoveDown)
                Spacer()
                Button("Delete Preset", role: .destructive, action: delete)
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Label {
                Text(preset.title.trimmed.isEmpty ? "Untitled" : preset.title)
                    .foregroundStyle(preset.title.trimmed.isEmpty ? .secondary : .primary)
            } icon: {
                Image(systemName: preset.shownSymbol).frame(width: 22)
            }
        }
        .contextMenu {
            Button("Move Left") { move(-1) }
                .disabled(!canMoveUp)
            Button("Move Right") { move(1) }
                .disabled(!canMoveDown)
            Divider()
            Button("Delete Preset", role: .destructive, action: delete)
        }
    }
}

/// A preset's icon, which opens a grid of icons to choose from and a field for any SF Symbol's name.
private struct SymbolPicker: View {
    @Binding var symbol: String
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Image(systemName: PromptPreset.exists(symbol) ? symbol : PromptPreset.fallbackSymbol)
                .frame(width: 30, height: 18)
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            SymbolGrid(symbol: $symbol) { isOpen = false }
        }
        .help("Choose an icon")
        .accessibilityLabel("Icon")
        .accessibilityValue(symbol)
    }
}

private struct SymbolGrid: View {
    @Binding var symbol: String
    let done: () -> Void
    @State private var name = ""

    private var typed: String { name.trimmed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8), spacing: 6) {
                ForEach(PromptPreset.symbols, id: \.self) { candidate in
                    let isChosen = candidate == symbol
                    Button {
                        symbol = candidate
                        done()
                    } label: {
                        Image(systemName: candidate)
                            .font(.system(size: 14))
                            .foregroundStyle(isChosen ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.primary))
                            .frame(width: 32, height: 32)
                            .background(isChosen ? AnyShapeStyle(Color.meralinePink.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
                            .contentShape(.rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(candidate)
                    .accessibilityLabel(candidate)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Any SF Symbol’s name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(useTyped)
                Text(typed.isEmpty || PromptPreset.exists(typed) ? "Such as pencil.and.scribble. Press Return to use it." : "macOS has no symbol by that name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 8 * 32 + 7 * 6 + 28)
        .onAppear { name = PromptPreset.symbols.contains(symbol) ? "" : symbol }
    }

    private func useTyped() {
        guard PromptPreset.exists(typed) else { return }
        symbol = typed
        done()
    }
}
