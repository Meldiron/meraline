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
    static let shared: Preferences = {
        #if DEBUG
        // Throwaway runs, such as scripts/screenshots.sh, keep their settings in a suite of their own so
        // the preferences of the copy you use are never touched. Debug builds only.
        if let suite = ProcessInfo.processInfo.environment["MERALINE_DEFAULTS_SUITE"], let defaults = UserDefaults(suiteName: suite) {
            return Preferences(defaults: defaults)
        }
        #endif
        return Preferences()
    }()

    static let defaultSystemPrompt = """
    You answer quick questions asked from a small floating window. Lead with the answer. \
    Keep it brief: a sentence or a short paragraph, or up to five bullets when a list is clearer. \
    Use Markdown bold, italics, inline code, and links only when they help. \
    Skip headings, preambles, and offers of further help.
    """

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: SecretStore

    /// Whether the panel asks an LLM or an agent. The toggle under the input switches it.
    var mode: ProviderKind {
        didSet {
            guard mode != oldValue else { return }
            saveChoices()
            Log.settings.info("Mode: \(mode.title)")
        }
    }
    /// The provider picked for each mode, from the sparkle menu or Settings. A mode without a pick, or
    /// whose pick is not ready, answers with its first ready provider.
    private var choices: [ProviderKind: Provider] {
        didSet { saveChoices() }
    }

    /// The provider picked for the current mode. Picking one of the other kind switches the mode too.
    var provider: Provider? {
        get { choices[mode] }
        set {
            guard let newValue else {
                choices[mode] = nil
                return
            }
            if choices[newValue.kind] != newValue {
                choices[newValue.kind] = newValue
                Log.settings.info("Default \(newValue.kind.title): \(newValue.name)")
            }
            mode = newValue.kind
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
    /// The shortcut brings the text selected in the app in front, or the files selected in Finder, once
    /// Meraline has Accessibility access.
    var bringsSelection: Bool {
        didSet { defaults.set(bringsSelection, forKey: "bringsSelection") }
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
        // "provider" is the provider of the current mode, as it was before there were modes. It wins over
        // the per-mode keys, so older preferences and `-provider claudeCode` on the command line still pick.
        let current = defaults.string(forKey: "provider").flatMap(Provider.init(rawValue:))
        var choices: [ProviderKind: Provider] = [:]
        for kind in ProviderKind.allCases {
            let saved = defaults.string(forKey: "provider.\(kind.rawValue)").flatMap(Provider.init(rawValue:))
            choices[kind] = saved?.kind == kind ? saved : nil
        }
        if let current { choices[current.kind] = current }
        self.choices = choices
        mode = current?.kind ?? defaults.string(forKey: "mode").flatMap(ProviderKind.init(rawValue:)) ?? .llm
        placement = defaults.string(forKey: "placement").flatMap(PanelPlacement.init(rawValue:)) ?? .screenCenter
        isPinned = defaults.bool(forKey: "isPinned")
        showsMenuBarIcon = defaults.object(forKey: "showsMenuBarIcon") as? Bool ?? true
        bringsSelection = defaults.object(forKey: "bringsSelection") as? Bool ?? true
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
                effort: defaults.string(forKey: "\(provider.rawValue).effort").flatMap(ReasoningEffort.init(rawValue:)) ?? .automatic,
                allowsMCP: defaults.object(forKey: "\(provider.rawValue).mcp") as? Bool ?? true,
                disabledMCPServers: Set(defaults.stringArray(forKey: "\(provider.rawValue).mcpOff") ?? []),
                knownMCPServers: defaults.stringArray(forKey: "\(provider.rawValue).mcpServers") ?? []
            ))
        })
        for kind in ProviderKind.allCases {
            if let chosen = self.choices[kind], !providerSettings[chosen]!.isReady(for: chosen) {
                self.choices[kind] = readyProviders(for: kind).first
            }
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
            defaults.set(newValue.allowsMCP, forKey: "\(provider.rawValue).mcp")
            defaults.set(newValue.disabledMCPServers.sorted(), forKey: "\(provider.rawValue).mcpOff")
            defaults.set(newValue.knownMCPServers, forKey: "\(provider.rawValue).mcpServers")
            if old.apiKey != newValue.apiKey { secrets.write(provider.rawValue, newValue.apiKey.trimmed) }
            reconcile(provider.kind)
        }
    }

    /// Every ready provider. A cloud provider comes before Apple Intelligence, so a configured one
    /// outranks the on-device fallback.
    var readyProviders: [Provider] {
        Provider.allCases.filter { providerSettings[$0]!.isReady(for: $0) }
    }

    func readyProviders(for kind: ProviderKind) -> [Provider] {
        readyProviders.filter { $0.kind == kind }
    }

    /// The provider that answers in the current mode, or nil when none of its kind is ready.
    var activeProvider: Provider? { defaultProvider(for: mode) }

    /// The provider a mode answers with: its pick when ready, otherwise its first ready provider.
    func defaultProvider(for kind: ProviderKind) -> Provider? {
        if let chosen = choices[kind], providerSettings[chosen]!.isReady(for: chosen) { return chosen }
        return readyProviders(for: kind).first
    }

    /// Picks a mode's provider without switching to that mode, as the pickers in Settings › General do.
    func setDefaultProvider(_ provider: Provider?, for kind: ProviderKind) {
        guard provider == nil || provider?.kind == kind, choices[kind] != provider else { return }
        choices[kind] = provider
        Log.settings.info("Default \(kind.title): \(provider?.name ?? "none")")
    }

    /// After a provider's settings change: a mode whose pick is no longer ready, or that has none yet,
    /// takes its first ready provider.
    private func reconcile(_ kind: ProviderKind) {
        if let chosen = choices[kind], providerSettings[chosen]!.isReady(for: chosen) { return }
        let first = readyProviders(for: kind).first
        if choices[kind] != first { choices[kind] = first }
    }

    private func saveChoices() {
        defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(choices[mode]?.rawValue, forKey: "provider")
        for kind in ProviderKind.allCases {
            defaults.set(choices[kind]?.rawValue, forKey: "provider.\(kind.rawValue)")
        }
    }
}
