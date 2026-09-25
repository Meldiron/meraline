import AppKit
import Foundation
import KeyboardShortcuts

/// The report behind Settings › About › Copy Diagnostics: versions, the machine, how providers are
/// set up, update state, and the recent log. It never includes a question, an answer, or a key, so
/// it is safe to paste into a public issue.
enum Diagnostics {
    struct UpdateStatus: Equatable {
        var isAvailable: Bool
        var channel: UpdateChannel
        var checksAutomatically: Bool
        var downloadsAutomatically: Bool
        var lastCheck: Date?
        var state: String
    }

    static func report(
        preferences: Preferences,
        updates: UpdateStatus,
        entries: [LogEntry] = LogBuffer.shared.entries,
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
        lines.append("### Settings")
        lines.append("- Default provider: \(preferences.activeProvider?.name ?? "none")")
        lines.append("- Shortcut: \(KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "none")")
        lines.append("- Window: \(preferences.placement.title), \(preferences.isPinned ? "stays open" : "closes when clicking elsewhere"), menu bar icon \(preferences.showsMenuBarIcon ? "on" : "off")")
        lines.append("- System prompt: \(preferences.systemPrompt == Preferences.defaultSystemPrompt ? "default" : "customized")")
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
        lines.append("### Recent log (\(entries.count) entries)")
        lines.append("```")
        for entry in entries {
            lines.append("\(entry.date.formatted(.iso8601)) [\(entry.category)] \(entry.level.rawValue): \(entry.message)")
        }
        lines.append("```")
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(_ report: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
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
            if let path = CommandLineClient.resolve(value)?.path { return redactingHome(path) }
            return "not found (\(value))"
        }
        guard let url = URL(string: value), let host = url.host() else { return value.isEmpty ? "default" : "invalid" }
        return url.port.map { "\(host):\($0)" } ?? host
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
