import Observation
import SwiftUI

enum SettingsPane: Hashable {
    case general
    case answers
    case provider(Provider)
    case softwareUpdate
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .answers: "Answers"
        case .provider(let provider): provider.name
        case .softwareUpdate: "Software Update"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .answers: "text.bubble.fill"
        case .provider(let provider): provider.symbol
        case .softwareUpdate: "arrow.triangle.2.circlepath"
        case .about: "sparkle"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .answers: .meralinePink
        case .provider(let provider): provider.tint
        case .softwareUpdate: .gray
        case .about: .meralineLavender
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
                sidebarSection([.general, .answers])
                sidebarSection(Provider.services.map(SettingsPane.provider), title: "Providers")
                sidebarSection(Provider.commandLineTools.map(SettingsPane.provider), title: "Command-Line Tools")
                sidebarSection([.softwareUpdate, .about])
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(215)
        } detail: {
            detail
                .navigationTitle(navigation.selection?.title ?? "")
        }
        .toolbar(removing: .sidebarToggle)
        .tint(.meralinePink)
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
        guard case .provider(let provider) = pane, preferences.activeProvider == provider else { return nil }
        return Text("Default")
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection ?? .general {
        case .general: GeneralPane(preferences: preferences)
        case .answers: AnswersPane(preferences: preferences)
        case .provider(let provider): ProviderPane(provider: provider, preferences: preferences).id(provider)
        case .softwareUpdate: SoftwareUpdatePane(updater: updater)
        case .about: AboutPane(updater: updater)
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
