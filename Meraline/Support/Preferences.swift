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

/// How long the window may stay hidden before the chat moves to Recent Chats and the next question starts fresh.
enum IdleReset: Int, CaseIterable, Identifiable {
    case never = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    var id: Self { self }

    var title: String {
        switch self {
        case .never: "Never"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .thirtyMinutes: "After 30 minutes"
        case .oneHour: "After 1 hour"
        }
    }

    var interval: TimeInterval? { self == .never ? nil : TimeInterval(rawValue * 60) }

    func hasExpired(since hiddenAt: Date?, now: Date = .now) -> Bool {
        guard let interval, let hiddenAt else { return false }
        return now.timeIntervalSince(hiddenAt) >= interval
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: Self { self }

    var title: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        }
    }

    var summary: String {
        switch self {
        case .stable: "Finished releases only."
        case .beta: "Early builds ahead of each release. They can have rough edges, and every stable release reaches this channel too."
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
        didSet {
            defaults.set(provider?.rawValue, forKey: "provider")
            if provider != oldValue { Log.settings.info("Default provider: \(provider?.name ?? "none")") }
        }
    }
    var placement: PanelPlacement {
        didSet { defaults.set(placement.rawValue, forKey: "placement") }
    }
    var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: "isPinned") }
    }
    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: "showsMenuBarIcon") }
    }
    var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: "systemPrompt") }
    }
    var updateChannel: UpdateChannel {
        didSet { defaults.set(updateChannel.rawValue, forKey: "updateChannel") }
    }
    var idleReset: IdleReset {
        didSet { defaults.set(idleReset.rawValue, forKey: "idleReset") }
    }
    private(set) var providerSettings: [Provider: ProviderSettings]

    /// `onDeviceModelAvailable` decides whether Apple Intelligence starts turned on. It is on by default
    /// wherever the Mac supports it, so a fresh install can answer before any key is added.
    init(
        defaults: UserDefaults = .standard,
        secrets: SecretStore = .keychain,
        onDeviceModelAvailable: Bool = AppleIntelligenceClient.isAvailable
    ) {
        self.defaults = defaults
        self.secrets = secrets
        provider = defaults.string(forKey: "provider").flatMap(Provider.init(rawValue:))
        placement = defaults.string(forKey: "placement").flatMap(PanelPlacement.init(rawValue:)) ?? .screenCenter
        isPinned = defaults.bool(forKey: "isPinned")
        showsMenuBarIcon = defaults.object(forKey: "showsMenuBarIcon") as? Bool ?? true
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? Self.defaultSystemPrompt
        updateChannel = defaults.string(forKey: "updateChannel").flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        idleReset = (defaults.object(forKey: "idleReset") as? Int).flatMap(IdleReset.init(rawValue:)) ?? .thirtyMinutes
        providerSettings = Dictionary(uniqueKeysWithValues: Provider.allCases.map { provider in
            (provider, ProviderSettings(
                model: defaults.string(forKey: "\(provider.rawValue).model") ?? provider.defaultModel,
                baseURL: defaults.string(forKey: "\(provider.rawValue).baseURL") ?? provider.defaultBaseURL,
                apiKey: provider.keyPolicy == .none ? "" : secrets.read(provider.rawValue),
                isEnabled: defaults.object(forKey: "\(provider.rawValue).enabled") as? Bool
                    ?? (provider.isOnDevice && onDeviceModelAvailable),
                allowsWebSearch: defaults.object(forKey: "\(provider.rawValue).webSearch") as? Bool ?? true,
                effort: defaults.string(forKey: "\(provider.rawValue).effort").flatMap(ReasoningEffort.init(rawValue:)) ?? .automatic
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
            defaults.set(newValue.allowsWebSearch, forKey: "\(provider.rawValue).webSearch")
            defaults.set(newValue.effort.rawValue, forKey: "\(provider.rawValue).effort")
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
