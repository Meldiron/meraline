import SwiftUI

/// The row under the input: the LLM and Agent toggle on the left, the games on the right. Both are small
/// glass groups in the panel's own language. The chosen item sits raised in glass with the faint pink tint
/// of the active pin, and the other items stay quiet until the pointer is over them.
struct ModeBar: View {
    let preferences: Preferences
    let session: ChatSession
    let focusInput: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ModeToggle(mode: preferences.mode, choose: switchMode)
            Spacer(minLength: 0)
            GameTray(playing: session.game) { game in
                session.startGame(game)
                focusInput()
            }
        }
    }

    private func switchMode(to mode: ProviderKind) {
        guard mode != preferences.mode else { return }
        preferences.mode = mode
        if preferences.activeProvider?.isOnDevice == true { AppleIntelligenceClient.prewarm() }
        focusInput()
    }
}

/// Two segments in a glass capsule. The chosen one carries a tinted glass pill that slides across when the
/// mode changes. ⌘1 and ⌘2 pick them from the keyboard.
private struct ModeToggle: View {
    let mode: ProviderKind
    let choose: (ProviderKind) -> Void
    @Namespace private var thumb
    @State private var hovered: ProviderKind?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProviderKind.allCases) { segment($0) }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: mode)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }

    /// A segment's place, 1 or 2, which is also its shortcut with ⌘.
    private func number(of kind: ProviderKind) -> Int {
        (ProviderKind.allCases.firstIndex(of: kind) ?? 0) + 1
    }

    private func segment(_ kind: ProviderKind) -> some View {
        let isOn = mode == kind
        let number = number(of: kind)
        return Button { choose(kind) } label: {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                Text(kind.title)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background {
                if isOn {
                    Color.clear
                        .glassEffect(.regular.tint(.meralinePink.opacity(0.22)).interactive(), in: .capsule)
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                } else if hovered == kind {
                    Capsule().fill(.primary.opacity(0.07))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
        .onHover { inside in
            if inside { hovered = kind } else if hovered == kind { hovered = nil }
        }
        .help(help(for: kind, number: number))
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func help(for kind: ProviderKind, number: Int) -> String {
        switch kind {
        case .llm: "Ask a model through its API or on this Mac (⌘\(number))"
        case .agent: "Ask an agent on this Mac that can use tools: Claude Code, Codex, or OpenCode (⌘\(number))"
        }
    }
}

/// The games as icon buttons, grouped in one glass capsule behind a controller. The game being played is
/// raised like the chosen mode. A button's tooltip says what its game is, and clicking one starts it,
/// or starts it over.
private struct GameTray: View {
    let playing: Game?
    let start: (Game) -> Void
    @State private var hovered: Game?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 26, height: 24)
                .help("Games")
                .accessibilityHidden(true)
            Capsule()
                .fill(.primary.opacity(0.12))
                .frame(width: 1, height: 14)
                .padding(.trailing, 3)
                .accessibilityHidden(true)
            ForEach(Game.allCases) { button(for: $0) }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: playing)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Games")
    }

    private func button(for game: Game) -> some View {
        let isPlaying = playing == game
        return Button { start(game) } label: {
            Image(systemName: game.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isPlaying ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background {
                    if isPlaying {
                        Color.clear
                            .glassEffect(.regular.tint(.meralinePink.opacity(0.22)).interactive(), in: .circle)
                    } else if hovered == game {
                        Circle().fill(.primary.opacity(0.07))
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = game } else if hovered == game { hovered = nil }
        }
        .help(isPlaying ? "\(game.title): playing now. Click to start over." : "\(game.title): \(game.summary)")
        .accessibilityLabel(game.title)
        .accessibilityHint(game.summary)
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
    }
}
