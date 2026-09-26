import Foundation
import Observation

/// The MCP servers each agent has listed for Meraline, refreshed in the background: at launch for the
/// agents that are turned on, and whenever an agent's Settings pane asks. Settings shows the list with a
/// toggle per server, and the names go into `ProviderSettings.knownMCPServers`, so a question can name
/// them right after launch, before the next refresh has come back.
@Observable
final class MCPServerRegistry {
    static let shared = MCPServerRegistry()

    private(set) var servers: [Provider: [MCPServer]] = [:]
    private(set) var refreshing: Set<Provider> = []
    private(set) var failures: [Provider: String] = [:]
    @ObservationIgnored private var tasks: [Provider: Task<Void, Never>] = [:]
    @ObservationIgnored private let list: @Sendable (Provider, String) async throws -> [MCPServer]

    /// `list` asks the agent; tests pass one that answers on its own.
    init(list: @escaping @Sendable (Provider, String) async throws -> [MCPServer] = MCPServerDiscovery.list) {
        self.list = list
    }

    /// Whether the agent has answered since launch.
    func hasListed(_ provider: Provider) -> Bool { servers[provider] != nil }

    /// Refreshes every agent that is ready and allowed to use MCP servers.
    func refreshAll(_ preferences: Preferences) {
        for provider in Provider.commandLineTools {
            let settings = preferences[provider]
            if settings.isReady(for: provider) && settings.allowsMCP { refresh(provider, preferences: preferences) }
        }
    }

    /// Asks the agent for its servers and remembers their names in `preferences`. A refresh already
    /// under way is left to finish.
    func refresh(_ provider: Provider, preferences: Preferences) {
        guard provider.supportsMCP, tasks[provider] == nil else { return }
        let command = preferences[provider].baseURL
        refreshing.insert(provider)
        failures[provider] = nil
        tasks[provider] = Task { [list] in
            defer {
                tasks[provider] = nil
                refreshing.remove(provider)
            }
            do {
                let listed = try await list(provider, command)
                servers[provider] = listed
                var settings = preferences[provider]
                settings.knownMCPServers = listed.filter(\.status.isUsable).map(\.name)
                preferences[provider] = settings
                Log.commandLine.info("\(provider.name) lists \(listed.count) MCP server(s), \(settings.allowedMCPServers.count) allowed here")
            } catch {
                failures[provider] = error.localizedDescription
                Log.commandLine.error("Listing MCP servers for \(provider.name) failed: \(error.localizedDescription)")
            }
        }
    }
}
