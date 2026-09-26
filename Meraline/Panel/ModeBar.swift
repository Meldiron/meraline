import SwiftUI

/// The row under the input: the LLM and Agent toggle on the left; on the right, the games behind a
/// controller and the recent chats behind a clock. All are small glass groups in the panel's own language.
/// The chosen item sits raised in glass with the faint pink tint of the active pin, and the other items
/// stay quiet until the pointer is over them.
struct ModeBar: View {
    /// A group on the right that opens and closes. One is open at a time, and `PanelLayout` keeps which,
    /// while the window is hidden too, until Meraline quits.
    enum Tray {
        case games
    }

    let preferences: Preferences
    let session: ChatSession
    let layout: PanelLayout
    let focusInput: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ModeToggle(mode: preferences.mode, choose: switchMode)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                let isOpen = layout.expandedTray == .games
                GameTray(openness: isOpen ? 1 : 0, isOpen: isOpen, playing: session.game) {
                    toggle(.games)
                } start: { game in
                    session.startGame(game)
                    focusInput()
                }
                HistoryButton(
                    count: session.history.count,
                    forgetting: layout.lastForgetting,
                    isOpen: layout.actionPanel?.kind == .history
                ) {
                    layout.toggleActionPanel(.history)
                }
            }
        }
    }

    /// Opens a tray, closing any other, or closes it. The tray lays out every frame of the spring itself
    /// (see `GameTray`), so nothing is inserted or removed while it moves.
    private func toggle(_ tray: Tray) {
        withAnimation(GameTray.spring) {
            layout.expandedTray = layout.expandedTray == tray ? nil : tray
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
                kind.image
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

/// The games as icon buttons in one glass capsule, behind a controller that opens and closes them. Closed,
/// only the controller shows, tinted pink while a game is on so the game isn't forgotten behind it. Open, the
/// controller keeps its place at the right end and the capsule stretches to its left, uncovering the games.
///
/// Every frame is laid out from `openness`, which SwiftUI springs from 0 to 1 and back: the capsule's width,
/// how much of the row of games shows, and each game's fade, growth, and focus, which follow the capsule's
/// edge as it passes. Nothing is inserted or removed while the tray moves, so nothing can land ahead of the
/// glass, and a click mid-way turns it around smoothly. The spring overshoots a little, which stretches the
/// glass past the row for a moment, as Liquid Glass does. The playing game's highlight is a flat tint rather
/// than glass, so no glass sits inside the moving glass.
struct GameTray: View, Animatable {
    var openness: Double
    let isOpen: Bool
    let playing: Game?
    let toggle: () -> Void
    let start: (Game) -> Void

    @State private var hovered: Game?
    @State private var isControllerHovered = false

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    static let spring = Animation.spring(duration: 0.46, bounce: 0.2)
    static let buttonSize: CGFloat = 24
    static let spacing: CGFloat = 2
    /// The line between the games and the controller, with its space.
    static let separatorWidth: CGFloat = 7
    /// How far past a game the capsule's edge goes before the game is fully there.
    private static let emergence: CGFloat = 20

    /// The width of the row of games, with its separator, all the way out.
    static var rowWidth: CGFloat {
        CGFloat(Game.allCases.count) * (buttonSize + spacing) + separatorWidth + spacing
    }

    /// How much of the row shows. Past 1, the spring's overshoot, the capsule stretches beyond the row.
    private var shownWidth: CGFloat { Self.rowWidth * CGFloat(max(0, openness)) }

    var body: some View {
        HStack(spacing: 0) {
            row
                .fixedSize()
                .frame(width: shownWidth, alignment: .trailing)
                .mask(alignment: .trailing) { edge }
            controller
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: playing)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: isControllerHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Games")
    }

    /// The games, then the separator, laid out at full width whatever shows of them.
    private var row: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Game.allCases) { game in
                button(for: game)
                    .modifier(Emergence(progress: progress(of: game)))
            }
            Capsule()
                .fill(.primary.opacity(0.12))
                .frame(width: 1, height: 14)
                .frame(width: Self.separatorWidth)
                .opacity(Double(min(1, shownWidth / Self.separatorWidth)))
                .accessibilityHidden(true)
        }
        .padding(.trailing, Self.spacing)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
    }

    /// The left edge of what shows fades over a few points while the capsule moves, so a game slides out
    /// from under the glass instead of being cut. Fully open, nothing fades.
    private var edge: some View {
        let fade = min(12, max(0, Self.rowWidth - shownWidth))
        return LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: shownWidth > 0 ? min(1, fade / shownWidth) : 1)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: shownWidth)
    }

    /// How far out a game is, 0 to 1: it starts as the capsule's edge reaches it and is fully there a little
    /// after the edge has passed it, and by the time the row is all out, the last game included. The game
    /// nearest the controller comes first.
    private func progress(of game: Game) -> Double {
        let index = Game.allCases.firstIndex(of: game) ?? 0
        let fromController = CGFloat(Game.allCases.count - 1 - index)
        let start = Self.spacing + Self.separatorWidth + Self.spacing + fromController * (Self.buttonSize + Self.spacing)
        let span = min(Self.buttonSize + Self.emergence, Self.rowWidth - start)
        return Double(min(1, max(0, (shownWidth - start) / span)))
    }

    /// The button that opens and closes the games. While they're closed and a game is on, it wears the
    /// game's pink in their place; the pink fades as the games come out.
    private var controller: some View {
        let closedness = 1 - min(1, max(0, openness))
        let standsForGame = playing != nil && closedness > 0.5
        return Button(action: toggle) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(standsForGame ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 24)
                .background {
                    ZStack {
                        Capsule().fill(Color.meralinePink.opacity(playing == nil ? 0 : 0.2 * closedness))
                        Capsule().fill(.primary.opacity(isControllerHovered ? 0.08 : 0.07 * (1 - closedness)))
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isControllerHovered = $0 }
        .help(controllerHelp)
        .accessibilityLabel(isOpen ? "Hide the games" : "Show the games")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    private var controllerHelp: String {
        if isOpen { return "Put the games away" }
        if let playing { return "\(playing.title) is on. Click for the games." }
        return "Games"
    }

    private func button(for game: Game) -> some View {
        let isPlaying = playing == game
        return Button { start(game) } label: {
            Image(systemName: game.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isPlaying ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background {
                    if isPlaying {
                        Circle().fill(Color.meralinePink.opacity(0.2))
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

/// A game coming out of the tray: it fades in, grows from a little smaller, and comes into focus.
private struct Emergence: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.6 + 0.4 * progress)
            .blur(radius: 3 * (1 - progress))
    }
}

/// The recent chats behind a clock that shows how many there are. A click opens their panel of actions,
/// where a chat reopens and Clear Recent Chats forgets them all after asking. When they are forgotten, by
/// that or by a shake of the window, the capsule says so for a moment in the pink of the active pin: the
/// count rolls down to nothing and the clock bounces.
private struct HistoryButton: View {
    let count: Int
    let forgetting: PanelLayout.Forgetting?
    let isOpen: Bool
    let toggle: () -> Void
    /// What the capsule says in place of the count, for a moment after the chats were forgotten.
    @State private var caption: String?
    @State private var captionTask: Task<Void, Never>?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 16)
                    .symbolEffect(.bounce, value: forgetting)
                if let caption {
                    Text(caption)
                        .transition(.blurReplace)
                } else {
                    Text("\(count)")
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .transition(.blurReplace)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(caption == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.meralinePink))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .glassEffect(glass, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .actionPanelAnchor(.history)
        .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: caption)
        .animation(.snappy(duration: 0.3), value: count)
        .help(help)
        .accessibilityLabel("Recent chats")
        .accessibilityValue(count == 1 ? "1 chat" : "\(count) chats")
        .onChange(of: forgetting) { _, forgetting in
            guard let forgetting else { return }
            say(forgetting.count > 0 ? "Forgotten" : "Nothing to forget")
        }
    }

    private var glass: Glass {
        if caption != nil { return .regular.tint(.meralinePink.opacity(0.22)).interactive() }
        return isOpen ? .regular.tint(.primary.opacity(0.08)).interactive() : .regular.interactive()
    }

    private var help: String {
        switch count {
        case 0: "No recent chats yet"
        case 1: "1 recent chat. Shake the window to forget it."
        default: "\(count) recent chats. Shake the window to forget them."
        }
    }

    private func say(_ text: String) {
        captionTask?.cancel()
        caption = text
        captionTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            caption = nil
        }
    }
}
