import SwiftUI
import UniformTypeIdentifiers

struct ChatPanelView: View {
    @Bindable var session: ChatSession
    let preferences: Preferences
    let layout: PanelLayout
    let onHeightChange: (CGFloat) -> Void
    let onClose: () -> Void
    let openSettings: () -> Void

    @FocusState private var isInputFocused: Bool
    @State private var conversationHeight: CGFloat = 0
    @State private var isDropTargeted = false

    private var hasConversation: Bool { !session.turns.isEmpty }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                inputRow
                if !session.draftImages.isEmpty {
                    DraftImageTray(images: session.draftImages, onRemove: session.removeImage)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if hasConversation {
                    Divider().padding(.horizontal, 18)
                    conversation
                }
                if let failure = session.failure {
                    FailureRow(message: failure, showsSettings: session.failureNeedsSettings, openSettings: openSettings)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else if !hasConversation && preferences.activeProvider == nil {
                    SetupRow(openSettings: openSettings)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
                if hasConversation {
                    footer
                }
            }
            .frame(width: PanelController.width)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(.tint, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: acceptDrop)
        .onChange(of: layout.focusRequest) { isInputFocused = true }
        .onChange(of: session.isStreaming) { if !session.isStreaming { isInputFocused = true } }
        .animation(.smooth(duration: 0.2), value: session.draftImages)
        .animation(.smooth(duration: 0.2), value: session.failure)
    }

    private var inputRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: session.isStreaming)

            TextField(hasConversation ? "Ask a follow-up…" : "Ask anything…", text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .lineLimit(1...8)
                .focused($isInputFocused)
                .onSubmit(session.send)
                .disabled(session.isStreaming)

            if session.isStreaming {
                Button(action: session.stop) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Stop")
                        Text("esc").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.glass)
                .fixedSize()
                .help("Stop answering")
            } else {
                ModelMenu(preferences: preferences, openSettings: openSettings)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(minHeight: 60)
    }

    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(session.turns) { turn in
                    TurnView(turn: turn, isAnswering: session.isStreaming && turn.id == session.turns.last?.id)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { conversationHeight = $0 }
        }
        .frame(height: min(conversationHeight, layout.maximumConversationHeight))
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let provider = preferences.activeProvider {
                Label(preferences[provider].model, systemImage: provider.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            FooterButton(title: "Copy Answer", symbol: "doc.on.doc", shortcut: KeyboardShortcut("c", modifiers: [.command, .shift])) {
                session.copyLastAnswer()
            }
            .disabled(session.lastAnswer == nil)
            FooterButton(title: "New Chat", symbol: "square.and.pencil", shortcut: KeyboardShortcut("n")) {
                session.reset()
                isInputFocused = true
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in session.attach(fileAt: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        if let image = NSImage(data: data) { session.attach(image) }
                    }
                }
            }
        }
        return accepted
    }
}

private struct ModelMenu: View {
    let preferences: Preferences
    let openSettings: () -> Void

    var body: some View {
        if let active = preferences.activeProvider {
            Menu {
                ForEach(preferences.readyProviders) { provider in
                    Toggle(isOn: Binding(
                        get: { provider == active },
                        set: { if $0 { preferences.provider = provider } }
                    )) {
                        Label("\(provider.name) — \(preferences[provider].model)", systemImage: provider.symbol)
                    }
                }
                Divider()
                Button("Settings…", action: openSettings)
            } label: {
                Label(preferences[active].model, systemImage: active.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 190)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .help("Choose the model that answers")
        } else {
            Button("Set Up", action: openSettings)
                .buttonStyle(.glassProminent)
        }
    }
}

private struct TurnView: View {
    let turn: ChatSession.Turn
    let isAnswering: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !turn.question.isEmpty {
                Text(turn.question)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !turn.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(turn.images) { AttachmentThumbnail(image: $0, size: 40) }
                }
            }
            if turn.answer.isEmpty && isAnswering {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                    .accessibilityLabel("Thinking")
            } else {
                Text(MarkdownText.render(turn.answer))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DraftImageTray: View {
    let images: [ImageAttachment]
    let onRemove: (ImageAttachment.ID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(images) { image in
                AttachmentThumbnail(image: image, size: 48)
                    .overlay(alignment: .topTrailing) {
                        Button { onRemove(image.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 18, height: 18)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove image")
                        .offset(x: 6, y: -6)
                    }
            }
            Spacer()
        }
    }
}

private struct AttachmentThumbnail: View {
    let image: ImageAttachment
    let size: CGFloat

    var body: some View {
        Group {
            if let nsImage = NSImage(data: image.data) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .accessibilityLabel("Attached image")
    }
}

private struct FailureRow: View {
    let message: String
    let showsSettings: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsSettings {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 16))
    }
}

private struct SetupRow: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect an AI provider")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add an API key or turn on a local model to start asking.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.glassProminent)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let shortcut: KeyboardShortcut
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: symbol)
                Text(shortcut.displayName)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .keyboardShortcut(shortcut)
    }
}

private extension KeyboardShortcut {
    var displayName: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + String(key.character).uppercased()
    }
}

enum MarkdownText {
    static func render(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}
