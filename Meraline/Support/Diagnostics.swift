import AppKit
import Foundation
import KeyboardShortcuts

/// The report behind Settings › About › Copy Diagnostics, the sparkle's panel, and the capsule that offers it after
/// a crash: versions, the machine, the crash macOS reported since the previous launch, how providers are set up,
/// update state, what the chats hold, and the recent log. It never includes a question, an answer, or a key,
/// so it is safe to paste into a public issue, and it is copied the same way whenever it is asked for.
enum Diagnostics {
    struct UpdateStatus: Equatable {
        var isAvailable: Bool
        var channel: UpdateChannel
        var checksAutomatically: Bool
        var downloadsAutomatically: Bool
        var lastCheck: Date?
        var state: String
    }

    /// What the chats hold in memory and their workspaces on disk, in counts and sizes only.
    struct Storage: Equatable {
        var openTurns = 0
        var recentChats = 0
        var chatBytes = 0
        var largestChatBytes = 0
        /// How long until the next chat's time runs out, if any chat is kept.
        var nextExpiry: TimeInterval?
        var workspaces = ChatWorkspace.Usage()
        var liveAgents = 0

        var summary: [String] {
            let open = openTurns > 0 ? "an open chat of \(openTurns) turn(s)" : "no open chat"
            let next = nextExpiry.map { "the next goes in \(Int(($0 / 60).rounded(.up))) min" } ?? "none kept"
            return [
                "- Chats in memory: \(open) and \(recentChats) recent (at most \(ChatSession.chatLimit.formatted()) in all), \(memory(chatBytes)) in all, the largest \(memory(largestChatBytes)) of \(memory(ChatSession.chatByteLimit))",
                "- Chat lifetime: \(Int(ChatSession.chatLifetime / 60)) minutes after the last message, \(next)",
                "- Workspaces: \(workspaces.folders) (at most \(ChatSession.chatLimit.formatted())), \(workspaces.items.formatted()) files and folders, \(Int64(workspaces.bytes).formatted(.byteCount(style: .file))), the fullest \(workspaces.mostItems.formatted()) of \(FileAttachment.folderLimit.formatted())",
                "- Workspaces of other Meraline processes: \(workspaces.otherProcesses)",
                "- Agents running: \(liveAgents) of \(LiveAgents.limit)"
            ]
        }

        private func memory(_ bytes: Int) -> String {
            Int64(bytes).formatted(.byteCount(style: .memory))
        }
    }

    /// Measures the chats of `session`, and walks their workspaces off the main thread, since a copied project
    /// can be thousands of files.
    static func storage(of session: ChatSession, now: Date = .now) async -> Storage {
        let sizes = [ChatSession.byteCount(of: session.turns)] + session.history.map(\.byteCount)
        let deadlines = session.history.map(\.expiresAt) + [session.expiresAt].compactMap { $0 }
        var storage = Storage(
            openTurns: session.turns.count,
            recentChats: session.history.count,
            chatBytes: sizes.reduce(0, +),
            largestChatBytes: sizes.max() ?? 0,
            nextExpiry: deadlines.min().map { max(0, $0.timeIntervalSince(now)) },
            liveAgents: LiveAgents.shared.count
        )
        storage.workspaces = await Task.detached(priority: .userInitiated) { ChatWorkspace.usage() }.value
        return storage
    }

    static func report(
        preferences: Preferences,
        updates: UpdateStatus,
        entries: [LogEntry] = LogBuffer.shared.entries,
        crash: CrashReport? = CrashNotice.shared.crash,
        storage: Storage? = nil,
        now: Date = .now
    ) -> String {
        var lines: [String] = []
        let bundle = Bundle.main
        lines.append("## Meraline diagnostics")
        lines.append("")
        lines.append("- Meraline \(bundle.shortVersion) (\(bundle.buildNumber))")
        lines.append("- macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(architecture)")
        lines.append("- Installed at \(redactingHome(bundle.bundlePath))\(locationWarning(bundle.bundlePath))")
        lines.append("- Generated \(now.formatted(.iso8601))")
        lines.append("")
        if let crash {
            lines.append("### Crash")
            lines.append(contentsOf: crash.summary)
            lines.append("")
        }
        lines.append("### Settings")
        lines.append("- Mode: \(preferences.mode.title), default LLM: \(preferences.defaultProvider(for: .llm)?.name ?? "none"), default agent: \(preferences.defaultProvider(for: .agent)?.name ?? "none")")
        lines.append("- Shortcut: \(KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "none")\(KeyboardShortcuts.isEnabled(for: .togglePanel) ? "" : ", not registered")")
        lines.append("- Window: \(preferences.placement.title), \(preferences.isPinned ? "stays open" : "closes when clicking elsewhere"), menu bar icon \(preferences.showsMenuBarIcon ? "on" : "off"), hidden from screen sharing \(preferences.hidesFromScreenSharing ? "on" : "off")")
        lines.append("- Forget chats: on sleep \(preferences.forgetsChatsOnSleep ? "on" : "off"), on lock \(preferences.forgetsChatsOnLock ? "on" : "off")")
        lines.append("- Selected text: \(preferences.bringsSelection ? "on" : "off"), Accessibility access \(SelectionAccess.shared.isGranted ? "allowed" : "not allowed")")
        lines.append("- Screenshots: Screen Recording access \(ScreenCapture.hasAccess ? "allowed" : "not allowed")")
        let changedPrompts = SystemPrompt.allCases.filter(preferences.isChanged).map(\.title)
        lines.append("- Prompts: \(changedPrompts.isEmpty ? "default" : "changed for \(changedPrompts.joined(separator: ", "))"), language \(preferences.language.name), presets \(preferences.arePresetsChanged ? "changed, \(preferences.presets.count) of them" : "default")")
        if updates.isAvailable {
            let lastCheck = updates.lastCheck.map { $0.formatted(.iso8601) } ?? "never"
            lines.append("- Updates: \(updates.channel.title.lowercased()) channel, automatic checks \(updates.checksAutomatically ? "on" : "off"), automatic install \(updates.downloadsAutomatically ? "on" : "off"), last check \(lastCheck), \(updates.state)")
        } else {
            lines.append("- Updates: not configured in this build")
        }
        lines.append("")
        lines.append("### Providers")
        lines.append("| Provider | State | Model | Endpoint |")
        lines.append("| --- | --- | --- | --- |")
        for provider in Provider.allCases {
            let settings = preferences[provider]
            lines.append("| \(provider.name) | \(state(of: settings, for: provider)) | \(settings.model.trimmed.isEmpty ? "default" : settings.model.trimmed) | \(endpoint(of: settings, for: provider)) |")
        }
        lines.append("")
        if let storage {
            lines.append("### Storage")
            lines.append(contentsOf: storage.summary)
            lines.append("")
        }
        lines.append("### Recent log (\(entries.count) entries)")
        lines.append("```")
        for entry in entries {
            lines.append("\(entry.date.formatted(.iso8601)) [\(entry.category)] \(entry.level.rawValue): \(entry.message)")
        }
        lines.append("```")
        return redacting(lines.joined(separator: "\n"), keys: Provider.allCases.map { preferences[$0].apiKey })
    }

    static func copyToPasteboard(_ report: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }

    /// What `text` says with the home folder written as `~`, since a log line's path names the person, and with
    /// each of `keys` taken out. No key should ever reach the log; this is so one that slipped into an error
    /// description still stays off the clipboard.
    static func redacting(_ text: String, keys: [String], home: String = NSHomeDirectory()) -> String {
        var text = text
        // Longer keys first, in case one holds another.
        for key in Set(keys.map(\.trimmed)).filter({ $0.count >= 8 }).sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: key, with: "[key]")
        }
        guard home.count > 1 else { return text }
        // Only the whole folder name: /Users/ann, not the start of /Users/anna.
        let pattern = NSRegularExpression.escapedPattern(for: home) + "(?![A-Za-z0-9._-])"
        return text.replacingOccurrences(of: pattern, with: "~", options: .regularExpression)
    }

    private static var architecture: String {
        #if arch(arm64)
        "Apple silicon"
        #else
        "Intel (or Rosetta)"
        #endif
    }

    private static func state(of settings: ProviderSettings, for provider: Provider) -> String {
        if settings.isReady(for: provider) { return "ready" }
        if provider.keyPolicy == .required { return settings.apiKey.trimmed.isEmpty ? "no key" : "not ready" }
        return settings.isEnabled ? "not ready" : "off"
    }

    private static func endpoint(of settings: ProviderSettings, for provider: Provider) -> String {
        let value = settings.baseURL.trimmed
        if provider.isCommandLine {
            let path = CommandLineClient.resolve(value).map { redactingHome($0.path) } ?? "not found (\(value))"
            return "\(path), \(mcpSummary(of: settings))"
        }
        guard let url = URL(string: value), let host = url.host() else { return value.isEmpty ? "default" : "invalid" }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// How many of the agent's MCP servers a question may use. Counts only, never names.
    private static func mcpSummary(of settings: ProviderSettings) -> String {
        guard settings.allowsMCP else { return "MCP off" }
        guard !settings.knownMCPServers.isEmpty else { return "no MCP servers listed" }
        return "MCP \(settings.allowedMCPServers.count) of \(settings.knownMCPServers.count) server(s)"
    }

    private static func redactingHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Running from a mounted disk image or from Downloads is the most common reason updates and
    /// the login item misbehave, so the report says so.
    private static func locationWarning(_ path: String) -> String {
        if path.hasPrefix("/Volumes/") { return " (running from a disk image; drag Meraline to Applications)" }
        if path.contains("/Downloads/") { return " (running from Downloads; move Meraline to Applications)" }
        return ""
    }
}
