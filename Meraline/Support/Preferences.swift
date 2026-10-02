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

extension UserDefaults {
    /// Where Meraline keeps what it remembers: the standard defaults, or, for throwaway runs of a Debug build
    /// such as scripts/screenshots.sh, the suite named by MERALINE_DEFAULTS_SUITE, so the preferences of the
    /// copy you use are never touched. Everything Meraline keeps goes through here.
    static let meraline: UserDefaults = {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["MERALINE_DEFAULTS_SUITE"], let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        #endif
        return .standard
    }()
}

@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: SecretStore

    /// Whether the panel asks an LLM, an agent, or a decision model. The toggle under the input switches it.
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
    /// Forget every chat when the Mac or its display goes to sleep (see `AwayWatcher`). Off unless you turn it on.
    var forgetsChatsOnSleep: Bool {
        didSet {
            guard forgetsChatsOnSleep != oldValue else { return }
            defaults.set(forgetsChatsOnSleep, forKey: "forgetsChatsOnSleep")
            Log.settings.info("Forget chats on sleep \(forgetsChatsOnSleep ? "on" : "off")")
        }
    }
    /// Forget every chat when the screen locks, or another user takes the screen (see `AwayWatcher`). Off unless
    /// you turn it on.
    var forgetsChatsOnLock: Bool {
        didSet {
            guard forgetsChatsOnLock != oldValue else { return }
            defaults.set(forgetsChatsOnLock, forKey: "forgetsChatsOnLock")
            Log.settings.info("Forget chats on lock \(forgetsChatsOnLock ? "on" : "off")")
        }
    }
    /// The prompts changed in Settings › Prompt. One left out says what it says by default.
    private var changedPrompts: [SystemPrompt: String]
    /// The presets of each mode as Settings › Prompt changed them; a mode left out has the defaults.
    private var changedPresets: [ProviderKind: [PromptPreset]]
    /// Under this confidence a decision shows as Not Sure, with the answer it leans to (see `Decision`).
    var unsureBelow: Double {
        didSet {
            guard unsureBelow != oldValue else { return }
            defaults.set(unsureBelow, forKey: "decisions.unsureBelow")
            Log.settings.info("Decisions not sure below \(Decision.percent(unsureBelow))")
        }
    }
    /// The answers a decision picks from when its question names none, written as `DecisionAnswers.text` is:
    /// “Yes / No” until changed.
    var decisionAnswers: String {
        didSet {
            guard decisionAnswers != oldValue else { return }
            defaults.set(decisionAnswers, forKey: "decisions.answers")
            Log.settings.info("Decision answers \(decisionAnswers == DecisionAnswers.defaultText ? "default" : "changed")")
        }
    }
    /// What a decision is about: the whole text, or each of its words or lines (see `DecisionScope`). The switch
    /// under the input in Decision mode sets it.
    var decisionScope: DecisionScope {
        didSet {
            guard decisionScope != oldValue else { return }
            defaults.set(decisionScope.rawValue, forKey: "decisions.scope")
            Log.settings.info("Decisions about \(decisionScope.title.lowercased())")
        }
    }
    /// The language answers, agents, and games are in (see `AnswerLanguage`).
    var language: AnswerLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: "language")
            Log.settings.info("Language: \(language.name)")
        }
    }
    var updateChannel: UpdateChannel {
        didSet { defaults.set(updateChannel.rawValue, forKey: "updateChannel") }
    }
    /// Asks macOS to leave the window out of screen sharing, recordings, and screenshots. Captures that take the
    /// whole display, as ScreenCaptureKit's do, may show it anyway. Off unless you turn it on.
    var hidesFromScreenSharing: Bool {
        didSet {
            guard hidesFromScreenSharing != oldValue else { return }
            defaults.set(hidesFromScreenSharing, forKey: "hidesFromScreenSharing")
            Log.settings.info("Hide from screen sharing \(hidesFromScreenSharing ? "on" : "off")")
        }
    }
    private(set) var providerSettings: [Provider: ProviderSettings]

    /// `onDeviceModelAvailable` decides whether Apple Intelligence starts turned on. It is on by default
    /// wherever the Mac supports it, so a fresh install can answer before any key is added.
    init(
        defaults: UserDefaults = .meraline,
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
        forgetsChatsOnSleep = defaults.bool(forKey: "forgetsChatsOnSleep")
        forgetsChatsOnLock = defaults.bool(forKey: "forgetsChatsOnLock")
        // Before each mode had a prompt of its own, one prompt went to both, so a change to it carries over to each.
        if let legacy = defaults.string(forKey: SystemPrompt.legacyKey) {
            if legacy != SystemPrompt.llm {
                for kind in ProviderKind.prompted where defaults.object(forKey: SystemPrompt.chat(kind).key) == nil {
                    defaults.set(legacy, forKey: SystemPrompt.chat(kind).key)
                }
            }
            defaults.removeObject(forKey: SystemPrompt.legacyKey)
        }
        var changedPrompts: [SystemPrompt: String] = [:]
        for prompt in SystemPrompt.allCases {
            guard let text = defaults.string(forKey: prompt.key) else { continue }
            if text == prompt.standard {
                defaults.removeObject(forKey: prompt.key)
            } else {
                changedPrompts[prompt] = text
            }
        }
        self.changedPrompts = changedPrompts
        var changedPresets: [ProviderKind: [PromptPreset]] = [:]
        for kind in ProviderKind.allCases {
            changedPresets[kind] = defaults.data(forKey: PromptPreset.key(for: kind)).flatMap { try? JSONDecoder().decode([PromptPreset].self, from: $0) }
        }
        self.changedPresets = changedPresets
        unsureBelow = defaults.object(forKey: "decisions.unsureBelow") as? Double ?? Decision.defaultUnsureBelow
        decisionAnswers = defaults.string(forKey: "decisions.answers") ?? DecisionAnswers.defaultText
        decisionScope = defaults.string(forKey: "decisions.scope").flatMap(DecisionScope.init(rawValue:)) ?? .whole
        language = defaults.string(forKey: "language").flatMap(AnswerLanguage.init(rawValue:)) ?? .english
        updateChannel = defaults.string(forKey: "updateChannel").flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        hidesFromScreenSharing = defaults.bool(forKey: "hidesFromScreenSharing")
        providerSettings = Dictionary(uniqueKeysWithValues: Provider.allCases.map { provider in
            (provider, ProviderSettings(
                model: defaults.string(forKey: "\(provider.rawValue).model") ?? provider.defaultModel,
                baseURL: defaults.string(forKey: "\(provider.rawValue).baseURL") ?? provider.defaultBaseURL,
                apiKey: provider.keyPolicy == .none ? "" : secrets.read(provider.keyAccount),
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
            if old.apiKey != newValue.apiKey {
                secrets.write(provider.keyAccount, newValue.apiKey.trimmed)
                // One account's key, pasted under either provider, serves both (see `Provider.sharesKey`).
                for twin in Provider.allCases where twin != provider && twin.keyAccount == provider.keyAccount {
                    providerSettings[twin]!.apiKey = newValue.apiKey
                    reconcile(twin.kind)
                }
            }
            reconcile(provider.kind)
        }
    }

    /// A prompt as Settings › Prompt has it. Setting it back to its default forgets the change.
    subscript(prompt prompt: SystemPrompt) -> String {
        get { changedPrompts[prompt] ?? prompt.standard }
        set {
            guard newValue != self[prompt: prompt] else { return }
            if newValue == prompt.standard {
                changedPrompts[prompt] = nil
                defaults.removeObject(forKey: prompt.key)
            } else {
                changedPrompts[prompt] = newValue
                defaults.set(newValue, forKey: prompt.key)
            }
        }
    }

    /// What a request sends for `prompt`: the prompt as Settings › Prompt has it, then the line for the language.
    func instructions(for prompt: SystemPrompt) -> String {
        [self[prompt: prompt], language.instruction(for: prompt) ?? ""].filter { !$0.trimmed.isEmpty }.joined(separator: "\n\n")
    }

    func isChanged(_ prompt: SystemPrompt) -> Bool {
        changedPrompts[prompt] != nil
    }

    /// A mode's presets above an empty chat, as Settings › Prompt has them (see `PromptPreset`). Setting them
    /// back to the defaults forgets the change, so they follow later defaults and the language again.
    subscript(presets kind: ProviderKind) -> [PromptPreset] {
        get { changedPresets[kind] ?? PromptPreset.defaults(for: kind, in: language) }
        set {
            guard newValue != self[presets: kind] else { return }
            if newValue == PromptPreset.defaults(for: kind, in: language) {
                changedPresets[kind] = nil
                defaults.removeObject(forKey: PromptPreset.key(for: kind))
            } else {
                changedPresets[kind] = newValue
                defaults.set(try? JSONEncoder().encode(newValue), forKey: PromptPreset.key(for: kind))
            }
        }
    }

    /// The presets of the current mode.
    var presets: [PromptPreset] {
        get { self[presets: mode] }
        set { self[presets: mode] = newValue }
    }

    func arePresetsChanged(for kind: ProviderKind) -> Bool { changedPresets[kind] != nil }

    /// The modes whose presets were changed, for the diagnostics.
    var changedPresetKinds: [ProviderKind] { ProviderKind.allCases.filter { changedPresets[$0] != nil } }

    var arePresetsChanged: Bool { !changedPresets.isEmpty }

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
