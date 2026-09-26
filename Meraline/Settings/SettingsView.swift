import Observation
import SwiftUI

enum SettingsPane: Hashable {
    case general
    case prompt
    case provider(Provider)
    case softwareUpdate
    case about

    /// A pane by the name `meraline://settings?pane=` uses: general, prompt, updates, about, or a
    /// provider's id such as claudeCode. Case doesn't matter.
    init?(named name: String) {
        switch name.lowercased() {
        case "general": self = .general
        case "prompt": self = .prompt
        case "updates", "softwareupdate": self = .softwareUpdate
        case "about": self = .about
        default:
            guard let provider = Provider.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { return nil }
            self = .provider(provider)
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .prompt: "Prompt"
        case .provider(let provider): provider.name
        case .softwareUpdate: "Software Update"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .prompt: "text.bubble.fill"
        case .provider(let provider): provider.symbol
        case .softwareUpdate: "arrow.triangle.2.circlepath"
        case .about: "sparkle"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .prompt: .gray
        case .provider(let provider): provider.tint
        case .softwareUpdate: .gray
        case .about: .gray
        }
    }
}

@Observable
final class SettingsNavigation {
    var selection: SettingsPane? = .general
}

struct SettingsView: View {
    let preferences: Preferences
    let updater: Updater
    @Bindable var navigation: SettingsNavigation
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                sidebarSection([.general, .prompt, .softwareUpdate, .about])
                sidebarSection(Provider.services.map(SettingsPane.provider), title: "LLMs")
                sidebarSection(Provider.commandLineTools.map(SettingsPane.provider), title: "Agents")
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(215)
        } detail: {
            detail
                .navigationTitle(navigation.selection?.title ?? "")
        }
        .toolbar(removing: .sidebarToggle)
    }

    @ViewBuilder
    private func sidebarSection(_ panes: [SettingsPane], title: String? = nil) -> some View {
        let visible = panes.filter { search.isEmpty || $0.title.localizedStandardContains(search) }
        if !visible.isEmpty {
            Section {
                ForEach(visible, id: \.self) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        SettingsIcon(symbol: pane.symbol, tint: pane.tint, size: 20)
                    }
                    .badge(badge(for: pane))
                    .tag(pane)
                }
            } header: {
                if let title { Text(title) }
            }
        }
    }

    private func badge(for pane: SettingsPane) -> Text? {
        guard case .provider(let provider) = pane, preferences.defaultProvider(for: provider.kind) == provider else { return nil }
        return Text("Default")
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .general {
        case .general: GeneralPane(preferences: preferences)
        case .prompt: PromptPane(preferences: preferences)
        case .provider(let provider): ProviderPane(provider: provider, preferences: preferences).id(provider)
        case .softwareUpdate: SoftwareUpdatePane(updater: updater)
        case .about: AboutPane(preferences: preferences, updater: updater)
        }
    }
}

struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct PaneHeader: View {
    let pane: SettingsPane
    let summary: String

    var body: some View {
        Section {
            VStack(spacing: 8) {
                SettingsIcon(symbol: pane.symbol, tint: pane.tint, size: 56)
                Text(pane.title)
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}
