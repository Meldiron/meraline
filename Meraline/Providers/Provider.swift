import SwiftUI

nonisolated enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic
    case openAI
    case gemini
    case openRouter
    case ollama
    case custom
    case claudeCode
    case codex
    case opencode
    case typeSafe
    case openRouterDecision
    // Last: the on-device model is the fallback, so it sorts after the configured providers of its kind.
    case apple

    static let services: [Provider] = [.apple, .anthropic, .openAI, .gemini, .openRouter, .ollama, .custom]
    static let commandLineTools: [Provider] = [.claudeCode, .codex, .opencode]
    /// The models that decide rather than write: a yes or no, one of a set of answers, or a level, with how sure
    /// they are (see `DecisionClient`): TypeSafe's Jev directly, or any System One model OpenRouter serves.
    static let decisionModels: [Provider] = [.typeSafe, .openRouterDecision]

    /// The System One models OpenRouter serves (`output_modalities=decisions` in its list), each run with
    /// Meraline's own requests on 2026-10-02: Jev, its always-newest alias, and the other labs' models that take a
    /// state of texts. Respan's Span-01 models are left out, since they read only a conversation transcript.
    static let openRouterDecisionModels = [
        "typesafe/jev-1.13", "~typesafe/jev-latest", "liquid/d1", "upstage/solar-decide",
        "jaredpalmer/kev-4b", "togethercomputer/tev1-4b-experimental", "inception/mercury-decide:free",
    ]

    var isCommandLine: Bool { Self.commandLineTools.contains(self) }
    var isDecisionModel: Bool { Self.decisionModels.contains(self) }

    /// Which of the panel's modes the provider answers in.
    var kind: ProviderKind { isDecisionModel ? .decision : isCommandLine ? .agent : .llm }

    /// The provider whose key this one uses, when the two are one account: OpenRouter's decision models take the
    /// key of OpenRouter under LLMs, so it is pasted once. Nil for a key of its own.
    var sharesKey: Provider? { self == .openRouterDecision ? .openRouter : nil }

    /// The Keychain item the key is kept under (see `Preferences`).
    var keyAccount: String { (sharesKey ?? self).rawValue }

    /// Runs on this Mac through Apple's Foundation Models framework: no key, no server, no command.
    var isOnDevice: Bool { self == .apple }

    /// Providers that can search the web when asked to.
    var supportsWebSearch: Bool { self == .claudeCode || self == .codex }

    /// The agents, which can use the MCP servers set up in them.
    var supportsMCP: Bool { isCommandLine }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama"
        case .custom: "Custom"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .apple: "Apple Intelligence"
        case .typeSafe: "TypeSafe"
        case .openRouterDecision: "OpenRouter"
        }
    }

    var summary: String {
        switch self {
        case .anthropic: "Claude models through the Messages API."
        case .openAI: "GPT models through the Responses API."
        case .gemini: "Gemini models through the Generative Language API."
        case .openRouter: "One key for hundreds of models from many labs."
        case .ollama: "Local models running on this Mac. No key needed."
        case .custom: "Any server that speaks the OpenAI Chat Completions API, such as LM Studio."
        case .claudeCode: "Answers from the claude command, using the account it’s signed in to and the MCP servers set up in it."
        case .codex: "Answers from the codex command, using the account it’s signed in to and its MCP servers, in a sandbox that writes only to the chat’s workspace and temporary folders."
        case .opencode: "Answers from the opencode command, using the providers and MCP servers configured in OpenCode."
        case .apple: "The on-device model built into macOS. Private, works offline, and needs no key. Best for short questions; it can’t browse the web."
        case .typeSafe: "Jev, TypeSafe’s decision model. It writes nothing: asked about the text you add, it answers yes or no, one of the answers you name, or a level, with how sure it is, in a fraction of a second."
        case .openRouterDecision: "Decision models from several labs, with the key you use for OpenRouter’s LLMs: TypeSafe’s Jev, Liquid’s D1, Upstage’s Solar Decide, and more. They write nothing: asked about the text you add, they answer yes or no, one of the answers you name, or a level, with how sure they are."
        }
    }

    var symbol: String {
        switch self {
        case .anthropic: "asterisk"
        case .openAI: "circle.hexagongrid.fill"
        case .gemini: "sparkle"
        case .openRouter: "arrow.triangle.branch"
        case .ollama: "desktopcomputer"
        case .custom: "server.rack"
        case .claudeCode: "terminal.fill"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .opencode: "curlybraces"
        case .apple: "apple.intelligence"
        case .typeSafe: "circle.lefthalf.filled"
        case .openRouterDecision: "arrow.triangle.branch"
        }
    }

    var tint: Color {
        switch self {
        case .anthropic: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .openAI: Color(red: 0.07, green: 0.64, blue: 0.50)
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .openRouter: Color(red: 0.42, green: 0.36, blue: 0.91)
        case .ollama: Color(white: 0.35)
        case .custom: Color(red: 0.55, green: 0.56, blue: 0.60)
        case .claudeCode: Color(red: 0.80, green: 0.42, blue: 0.30)
        case .codex: Color(red: 0.13, green: 0.13, blue: 0.15)
        case .opencode: Color(red: 0.30, green: 0.33, blue: 0.40)
        case .apple: Color(red: 0.44, green: 0.42, blue: 0.78)
        case .typeSafe: Color(red: 0.16, green: 0.53, blue: 0.6)
        case .openRouterDecision: Color(red: 0.42, green: 0.36, blue: 0.91)
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5"
        case .openAI: "gpt-5-mini"
        case .gemini: "gemini-3.6-flash"
        case .openRouter: "anthropic/claude-sonnet-5"
        case .ollama: "llama3.2"
        case .typeSafe: "jev-latest"
        case .openRouterDecision: "typesafe/jev-1.13"
        case .custom, .claudeCode, .codex, .opencode, .apple: ""
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .anthropic: ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5", "claude-fable-5-1"]
        case .openAI: ["gpt-5-mini", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]
        case .gemini: ["gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite"]
        case .openRouter: ["anthropic/claude-sonnet-5", "openai/gpt-5-mini", "google/gemini-3.6-flash"]
        case .ollama: ["llama3.2", "qwen3", "gemma3", "mistral"]
        case .custom, .opencode, .apple: []
        case .claudeCode: ["sonnet", "opus", "haiku"]
        case .codex: ["gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.6-luna"]
        case .typeSafe: ["jev-latest", "jev-preview", "jev-1.13.0"]
        case .openRouterDecision: Self.openRouterDecisionModels
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .ollama: "http://127.0.0.1:11434"
        case .custom: "http://127.0.0.1:1234/v1"
        case .claudeCode: "claude"
        case .codex: "codex"
        case .opencode: "opencode"
        case .apple: ""
        case .typeSafe: "https://api.typesafe.ai/v1"
        case .openRouterDecision: "https://openrouter.ai/api/v1"
        }
    }

    var keyPolicy: KeyPolicy {
        switch self {
        case .anthropic, .openAI, .gemini, .openRouter, .typeSafe, .openRouterDecision: .required
        case .custom: .optional
        case .ollama, .claudeCode, .codex, .opencode, .apple: .none
        }
    }

    var keyPortal: URL? {
        switch self {
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")
        case .ollama: URL(string: "https://ollama.com/download")
        case .custom: nil
        case .claudeCode: URL(string: "https://code.claude.com/docs/en/setup")
        case .codex: URL(string: "https://developers.openai.com/codex/cli")
        case .opencode: URL(string: "https://opencode.ai/docs")
        case .apple: nil
        case .typeSafe: URL(string: "https://console.typesafe.ai/keys")
        case .openRouterDecision: URL(string: "https://openrouter.ai/settings/keys")
        }
    }

    /// Where the agent explains MCP servers, for the MCP Servers section in Settings.
    var mcpPortal: URL? {
        switch self {
        case .claudeCode: URL(string: "https://code.claude.com/docs/en/mcp")
        case .codex: URL(string: "https://developers.openai.com/codex/mcp")
        case .opencode: URL(string: "https://opencode.ai/docs/mcp-servers")
        default: nil
        }
    }

    enum KeyPolicy {
        case required
        case optional
        case none
    }
}

/// The panel's three modes: a model answering through its API or on this Mac, an agent on this Mac that can
/// use tools, or a decision model that answers yes or no, one of your answers, or a level about the text you
/// add (see `Decision`). The toggle under the input switches between them, and each keeps its own provider.
nonisolated enum ProviderKind: String, CaseIterable, Identifiable, Sendable {
    case llm
    case agent
    case decision

    var id: Self { self }

    /// The modes that send a system prompt, which Settings › Prompt edits. A decision model takes none.
    static let prompted: [ProviderKind] = [.llm, .agent]

    var hasSystemPrompt: Bool { Self.prompted.contains(self) }

    var title: String {
        switch self {
        case .llm: "LLM"
        case .agent: "Agent"
        case .decision: "Decision"
        }
    }

    /// The Settings sidebar section, and the sparkle menu's header.
    var pluralTitle: String {
        switch self {
        case .llm: "LLMs"
        case .agent: "Agents"
        case .decision: "Decision Models"
        }
    }

    /// The mode's picture: a speech bubble, Meraline's own robot head, a custom symbol in the asset catalog that
    /// behaves like a system one, or a pair of scales.
    var image: Image {
        switch self {
        case .llm: Image(systemName: "bubble.left")
        case .agent: Image("robot")
        case .decision: Image(systemName: "scale.3d")
        }
    }

    /// The providers of this kind, in the order Settings lists them.
    var providers: [Provider] {
        switch self {
        case .llm: Provider.services
        case .agent: Provider.commandLineTools
        case .decision: Provider.decisionModels
        }
    }

    /// The mode after this one, around the toggle: `meraline://mode` alone switches to it.
    var next: ProviderKind {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

nonisolated struct ProviderSettings: Equatable, Sendable {
    var model: String
    var baseURL: String
    var apiKey: String
    var isEnabled: Bool
    var allowsWebSearch = true
    var effort = ReasoningEffort.automatic
    /// Agents only: whether the MCP servers set up in the agent may help answer questions asked here.
    var allowsMCP = true
    /// Servers turned off in Settings, by name. They stay set up in the agent.
    var disabledMCPServers: Set<String> = []
    /// The servers the agent listed the last time Meraline asked, so a question can name them right
    /// after launch, before the list is refreshed.
    var knownMCPServers: [String] = []

    /// The servers a question may use: the known ones, minus those turned off here.
    var allowedMCPServers: [String] {
        guard allowsMCP else { return [] }
        return knownMCPServers.filter { !disabledMCPServers.contains($0) }
    }

    func isReady(for provider: Provider) -> Bool {
        if provider.isOnDevice { return isEnabled }
        if provider.isCommandLine { return isEnabled && !baseURL.trimmed.isEmpty }
        let hasModel = !model.trimmed.isEmpty && !baseURL.trimmed.isEmpty
        switch provider.keyPolicy {
        case .required: return hasModel && !apiKey.trimmed.isEmpty
        case .optional, .none: return hasModel && isEnabled
        }
    }
}

nonisolated enum ReasoningEffort: String, CaseIterable, Identifiable, Sendable {
    case automatic = ""
    case low
    case medium
    case high

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Default"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
