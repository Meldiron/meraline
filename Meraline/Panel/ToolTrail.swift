import SwiftUI

/// Where a Why? stands: asking, the reason, or why there is none.
enum WhyAnswer: Equatable {
    case asking
    case reason(String)
    case failed(String)

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

/// A Why?'s one line, on an agent's ask and under the tools an answer used: asking, then the reason, or why
/// there is none.
struct WhyLine: View {
    let why: WhyAnswer
    let agent: String

    var body: some View {
        switch why {
        case .asking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Asking \(agent) why…")
            }
        case .reason(let reason):
            Text(reason)
                .textSelection(.enabled)
        case .failed(let message):
            Text("Couldn’t find out why. \(message)")
        }
    }
}

/// The tools an answer used, as small capsules under it: a web search, a page, a command, or an MCP tool
/// under its server's name. Hovering shows the full line. Once the answer is finished, a click on a capsule has
/// the provider that used the tool say why, in one line under the row (see `ToolReason`), and a click on it
/// again folds the line away. Neutral glass, like everything else here; the capsule the line speaks of looks
/// like the mode toggle's chosen segment.
struct ToolTrail: View {
    let tools: [Activity]
    /// Who used the tools, for the line and the hover text.
    var agent = "The agent"
    /// Asks why the tool at an index was used. Nil while the answer is coming, or when the provider that
    /// answered can't be asked any more; the capsules are then only capsules.
    var explain: ((Int) async throws -> String)?

    /// The capsule whose line shows, and what each capsule's Why? came to. Kept by the trail alone, so the
    /// reasons go with the chat.
    @State private var shown: Int?
    @State private var reasons: [Int: WhyAnswer] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6, maximumItemWidth: 260) {
                ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                    if explain == nil {
                        label(for: tool, isShown: false)
                            .glassEffect(.regular, in: .capsule)
                            .help(tool.title)
                    } else {
                        capsule(for: tool, at: index)
                    }
                }
            }
            .accessibilityElement(children: explain == nil ? .ignore : .contain)
            .accessibilityLabel("Used \(tools.map(\.label).formatted(.list(type: .and)))")
            if let shown, let why = reasons[shown] {
                WhyLine(why: why, agent: agent)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 9)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: ChatPanelView.cardAnimation), value: shown)
        .task(id: shown) {
            guard let index = shown, reasons[index] == .asking, let explain else { return }
            do {
                reasons[index] = .reason(try await explain(index))
                Log.chat.info("Reason for a tool shown")
            } catch {
                // Folded away, or another capsule clicked: the next click on this one asks again.
                guard !Task.isCancelled else {
                    if shown != index, reasons[index] == .asking { reasons[index] = nil }
                    return
                }
                Log.chat.error("Couldn’t get the reason for a tool: \(error.localizedDescription)")
                reasons[index] = .failed(error.localizedDescription)
            }
        }
    }

    private func capsule(for tool: Activity, at index: Int) -> some View {
        let isShown = shown == index
        return Button { toggle(index) } label: {
            label(for: tool, isShown: isShown)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isShown ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
        .help("\(tool.title). Click to ask \(agent) why.")
        .accessibilityLabel(tool.title)
        .accessibilityHint("Asks \(agent) why it did this")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    private func label(for tool: Activity, isShown: Bool) -> some View {
        Label {
            Text(tool.label)
                .fontWeight(isShown ? .semibold : .medium)
                .foregroundStyle(isShown ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        } icon: {
            Image(systemName: tool.symbol)
                .foregroundStyle(isShown ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
    }

    /// Shows the capsule's line, asking again when it has no reason yet, or folds it away when it shows.
    private func toggle(_ index: Int) {
        guard shown != index else {
            shown = nil
            return
        }
        if reasons[index] == nil || reasons[index]?.isFailed == true { reasons[index] = .asking }
        shown = index
    }
}
