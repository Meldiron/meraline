import Foundation
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.option]))
}

enum PanelPlacement: String, CaseIterable, Identifiable {
    case screenCenter
    case pointer
    case lastPosition

    var id: Self { self }

    var title: String {
        switch self {
        case .screenCenter: "Center of Screen"
        case .pointer: "Near Pointer"
        case .lastPosition: "Where I Left It"
        }
    }
}

@Observable
final class Preferences {
    static let shared = Preferences()

    static let defaultSystemPrompt = """
    You answer quick questions asked from a small floating window. Lead with the answer. \
    Keep it brief: a sentence or a short paragraph, or up to five bullets when a list is clearer. \
    Use Markdown bold, italics, inline code, and links only when they help. \
    Skip headings, preambles, and offers of further help.
    """

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: SecretStore

    var provider: Provider? {
        didSet { defaults.set(provider?.rawValue, forKey: "provider") }
    }
    var placement: PanelPlacement {
        didSet { defaults.set(placement.rawValue, forKey: "placement") }
    }
    var closesOnDeactivation: Bool {
        didSet { defaults.set(closesOnDeactivation, forKey: "closesOnDeactivation") }
    }
    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: "showsMenuBarIcon") }
    }
    var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: "systemPrompt") }
    }
    private(set) var providerSettings: [Provider: ProviderSettings]

    init(defaults: UserDefaults = .standard, secrets: SecretStore = .keychain) {
        self.defaults = defaults
        self.secrets = secrets
        provider = defaults.string(forKey: "provider").flatMap(Provider.init(rawValue:))
        placement = defaults.string(forKey: "placement").flatMap(PanelPlacement.init(rawValue:)) ?? .screenCenter
        closesOnDeactivation = defaults.object(forKey: "closesOnDeactivation") as? Bool ?? false
        showsMenuBarIcon = defaults.object(forKey: "showsMenuBarIcon") as? Bool ?? true
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? Self.defaultSystemPrompt
        providerSettings = Dictionary(uniqueKeysWithValues: Provider.allCases.map { provider in
            (provider, ProviderSettings(
                model: defaults.string(forKey: "\(provider.rawValue).model") ?? provider.defaultModel,
                baseURL: defaults.string(forKey: "\(provider.rawValue).baseURL") ?? provider.defaultBaseURL,
                apiKey: provider.keyPolicy == .none ? "" : secrets.read(provider.rawValue),
                isEnabled: defaults.bool(forKey: "\(provider.rawValue).enabled")
            ))
        })
        if let provider, !readyProviders.contains(provider) {
            self.provider = readyProviders.first
        }
    }

    subscript(provider: Provider) -> ProviderSettings {
        get { providerSettings[provider]! }
        set {
            let old = providerSettings[provider]!
            guard old != newValue else { return }
            providerSettings[provider] = newValue
            defaults.set(newValue.model, forKey: "\(provider.rawValue).model")
            defaults.set(newValue.baseURL, forKey: "\(provider.rawValue).baseURL")
            defaults.set(newValue.isEnabled, forKey: "\(provider.rawValue).enabled")
            if old.apiKey != newValue.apiKey { secrets.write(provider.rawValue, newValue.apiKey.trimmed) }
            reconcileActiveProvider()
        }
    }

    var readyProviders: [Provider] {
        Provider.allCases.filter { providerSettings[$0]!.isReady(for: $0) }
    }

    var activeProvider: Provider? {
        guard let provider, providerSettings[provider]!.isReady(for: provider) else { return readyProviders.first }
        return provider
    }

    private func reconcileActiveProvider() {
        let ready = readyProviders
        if let provider, ready.contains(provider) { return }
        provider = ready.first
    }
}
