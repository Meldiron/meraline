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

    static let services: [Provider] = [.anthropic, .openAI, .gemini, .openRouter, .ollama, .custom]
    static let commandLineTools: [Provider] = [.claudeCode, .codex, .opencode]

    var isCommandLine: Bool { Self.commandLineTools.contains(self) }

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
        case .claudeCode: "Answers from the claude command, using the account it’s signed in to. Tools stay off."
        case .codex: "Answers from the codex command, using the account it’s signed in to, in a read-only sandbox."
        case .opencode: "Answers from the opencode command, using the providers configured in OpenCode."
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
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5"
        case .openAI: "gpt-5-mini"
        case .gemini: "gemini-3.6-flash"
        case .openRouter: "anthropic/claude-sonnet-5"
        case .ollama: "llama3.2"
        case .custom, .claudeCode, .codex, .opencode: ""
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .anthropic: ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5", "claude-fable-5-1"]
        case .openAI: ["gpt-5-mini", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]
        case .gemini: ["gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite"]
        case .openRouter: ["anthropic/claude-sonnet-5", "openai/gpt-5-mini", "google/gemini-3.6-flash"]
        case .ollama: ["llama3.2", "qwen3", "gemma3", "mistral"]
        case .custom, .opencode: []
        case .claudeCode: ["sonnet", "opus", "haiku"]
        case .codex: ["gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.6-luna"]
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
        }
    }

    var keyPolicy: KeyPolicy {
        switch self {
        case .anthropic, .openAI, .gemini, .openRouter: .required
        case .custom: .optional
        case .ollama, .claudeCode, .codex, .opencode: .none
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
        }
    }

    enum KeyPolicy {
        case required
        case optional
        case none
    }
}

nonisolated struct ProviderSettings: Equatable, Sendable {
    var model: String
    var baseURL: String
    var apiKey: String
    var isEnabled: Bool

    func isReady(for provider: Provider) -> Bool {
        if provider.isCommandLine { return isEnabled && !baseURL.trimmed.isEmpty }
        let hasModel = !model.trimmed.isEmpty && !baseURL.trimmed.isEmpty
        switch provider.keyPolicy {
        case .required: return hasModel && !apiKey.trimmed.isEmpty
        case .optional, .none: return hasModel && isEnabled
        }
    }
}

nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
