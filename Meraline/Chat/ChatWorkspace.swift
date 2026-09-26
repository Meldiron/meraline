import Foundation

/// An empty temporary folder an agent gets for one chat: its working directory, where it may keep files
/// between questions. Made on the first question to an agent, it lives as long as the chat, in Recent
/// Chats included, and goes when the chat does or when Meraline quits. Each Meraline process keeps its
/// workspaces under its own process id, so a second copy (the test host, say) never removes a running
/// one's; what a crash left behind goes at the next launch.
nonisolated struct ChatWorkspace: Equatable, Sendable {
    static let parent = FileManager.default.temporaryDirectory.appending(path: "Meraline/Workspaces")
    static let defaultRoot = parent.appending(path: String(ProcessInfo.processInfo.processIdentifier))

    let url: URL

    static func make(in root: URL = defaultRoot) throws -> ChatWorkspace {
        let url = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ChatWorkspace(url: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes every workspace of this process, at quit.
    static func removeAll(in root: URL = defaultRoot) {
        try? FileManager.default.removeItem(at: root)
    }

    /// Removes the workspaces of Meraline processes that are gone, at launch: what a crash left behind.
    static func removeStale(in parent: URL = parent) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
        for name in names {
            guard let pid = pid_t(name), pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if kill(pid, 0) != 0 && errno == ESRCH {
                try? FileManager.default.removeItem(at: parent.appending(path: name))
            }
        }
    }
}
