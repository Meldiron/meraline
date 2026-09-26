import KeyboardShortcuts
import SwiftUI

/// What the window shows: the shortcut picker on the first launch, until it is answered or put away, and the
/// chat otherwise. The chat fades in when the picker is done, with the keyboard in its input.
struct PanelRoot: View {
    let setup: ShortcutSetup
    let chat: ChatPanelView
    let onHeightChange: (CGFloat) -> Void
    let focusInput: () -> Void

    var body: some View {
        Group {
            if setup.isPresented {
                ShortcutPicker(setup: setup, onHeightChange: onHeightChange)
                    .transition(.identity)
            } else {
                chat
                    .onAppear(perform: focusInput)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: setup.isPresented)
    }
}

/// The picker, in the window's own glass: keep ⌥ Space when it looks free, or pick one of the suggestions or a
/// shortcut of your own when it looks taken, then press it once to see the window answer. Neutral glass, with
/// the faint pink of the panel's buttons on the choice Return makes.
struct ShortcutPicker: View {
    let setup: ShortcutSetup
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.meraline)
                    .symbolEffect(.bounce, value: isWorked)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 20)
            .padding(.trailing, 18)
            .padding(.vertical, 18)
            .frame(width: PanelController.width)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        }
        .padding(PanelController.margin)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.2), value: setup.step)
        .animation(.smooth(duration: 0.2), value: setup.problem)
        .animation(.smooth(duration: 0.2), value: setup.isTrialQuiet)
    }

    private var isWorked: Bool {
        if case .worked = setup.step { true } else { false }
    }

    private var current: String { setup.current.spokenKeys }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch (setup.step, setup.conflict) {
        case (.trial, _), (.worked, _): "Ask with a shortcut."
        case (_, .system?): "macOS already uses \(current)."
        case (_, .taken?): "\(current) is already in use on this Mac."
        case (_, .apps?): "\(current) may already be taken."
        case (_, nil): "Ask with a shortcut."
        }
    }

    private var subtitle: String {
        switch (setup.step, setup.conflict) {
        case (.trial, _): "Press it now to try."
        case (.worked, _): "It works. Press it whenever you have a question."
        case (_, .apps(let names)?): "\(ShortcutRival.sentence(naming: names)) on this Mac and usually answer\(names.count == 1 ? "s" : "") it. Pick one Meraline can own."
        case (.pick, nil): "Pick the one you like, then press it once to try it."
        case (_, nil) where setup.current == .optionSpace: "⌥ Space is popular. ChatGPT, Gemini, and Raycast often use it too."
        case (_, nil): "Meraline opens with \(current)."
        case (_, _?): "Pick one Meraline can own."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch setup.step {
        case .offer:
            offer
        case .pick:
            ShortcutChoices(setup: setup)
        case .trial(let shortcut):
            trial(shortcut, worked: false)
        case .worked(let shortcut):
            trial(shortcut, worked: true)
        }
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Keep \(current)", action: setup.keep)
                    .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("Pick Another", action: setup.pickAnother)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            Text("You can change this later in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func trial(_ shortcut: KeyboardShortcuts.Shortcut, worked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Keycaps(keys: shortcut.keys, size: 22)
                if worked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityHidden(true)
                }
            }
            if setup.isTrialQuiet {
                Label("Pressed it and nothing happened? Another app may be holding it.", systemImage: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            if !worked {
                HStack(spacing: 8) {
                    Button("Try Another", action: setup.tryAnother)
                        .buttonStyle(.glass)
                    Button("Use This Shortcut") { setup.use(shortcut) }
                        .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
    }
}

/// The suggestions as large keycaps, the first one recommended, and a recorder for a shortcut of your own. The
/// line under them says where the keys are, for the one under the pointer.
private struct ShortcutChoices: View {
    let setup: ShortcutSetup

    @State private var hovered: ShortcutSuggestion?
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(setup.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    chip(suggestion, isRecommended: index == 0)
                }
            }
            Text(hovered?.hint ?? "Choose one to try it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.15), value: hovered)
            if let problem = setup.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            HStack(spacing: 10) {
                if isRecording {
                    KeyboardShortcuts.Recorder(for: .shortcutTrial) { shortcut in
                        if let shortcut { setup.tryShortcut(shortcut) }
                    }
                    // The recorder's own alerts would open as sheets on this borderless window; the picker says
                    // why a shortcut can't be used instead. Menu commands still can't be taken.
                    .keyboardShortcutsConflictPolicy(.init(menuItem: .block, systemShortcut: .allow, disallowed: .allow))
                    .frame(width: 180)
                    .transition(.opacity)
                } else {
                    Button("Record Your Own…") { isRecording = true }
                        .buttonStyle(.glass)
                }
                Spacer(minLength: 0)
                if setup.conflict?.isGuess != false {
                    Button("Keep \(setup.current.spokenKeys)\(setup.conflict == nil ? "" : " Anyway")", action: setup.keep)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help(setup.conflict == nil ? "Keep the shortcut Meraline has" : "Keep it if you moved those apps to other shortcuts")
                }
            }
            .animation(.smooth(duration: 0.2), value: isRecording)
        }
    }

    private func chip(_ suggestion: ShortcutSuggestion, isRecommended: Bool) -> some View {
        Button { setup.tryShortcut(suggestion.shortcut) } label: {
            VStack(spacing: 8) {
                Keycaps(keys: suggestion.shortcut.keys, size: 16)
                Text(isRecommended ? "Works well with others" : " ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .glassEffect(isRecommended ? .regular.tint(.meralinePink.opacity(0.12)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 16))
        .modifier(DefaultActionIf(isRecommended))
        .onHover { inside in
            if inside { hovered = suggestion } else if hovered == suggestion { hovered = nil }
        }
        .help(suggestion.hint)
        .accessibilityLabel("Try \(suggestion.shortcut.spokenKeys)\(isRecommended ? ", recommended" : "")")
        .accessibilityHint(suggestion.hint)
    }
}

/// Return tries the recommended suggestion.
private struct DefaultActionIf: ViewModifier {
    let isOn: Bool

    init(_ isOn: Bool) { self.isOn = isOn }

    func body(content: Content) -> some View {
        if isOn { content.keyboardShortcut(.defaultAction) } else { content }
    }
}

/// A shortcut as the keys on a keyboard, each in a small rounded cap.
struct Keycaps: View {
    let keys: [String]
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: size, weight: .medium))
                    .padding(.horizontal, size * 0.5)
                    .frame(minWidth: size * 1.9, minHeight: size * 1.9)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: size * 0.4))
                    .overlay { RoundedRectangle(cornerRadius: size * 0.4).strokeBorder(.primary.opacity(0.14)) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

/// Under the empty input after the picker was put away: the shortcut may belong to another app. The label opens
/// Settings › General on the recorder, and the cross hides it for good. Neutral glass, like the other rows.
struct ShortcutNotice: View {
    let change: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: change) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                    Text("Shortcut might conflict. Change it here")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .help("\(shortcut) may belong to another app. Pick another in Settings › General.")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .help("Hide this")
            .accessibilityLabel("Dismiss")
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var shortcut: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.spokenKeys ?? "The shortcut"
    }
}
