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

    /// Whether the folder is still there. macOS clears old files out of the temporary folder, so a chat kept long
    /// enough can find its workspace gone.
    var exists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Makes the folder again, empty, after it went missing. The chat's agent started in the old one, so it ends,
    /// and the next question starts one here.
    func remake() throws {
        LiveAgents.shared.end(workspace: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// A copied project can be thousands of files, so the folder is moved aside at once and deleted in the
    /// background. Whatever is left at quit goes with the rest of this process's workspaces.
    func remove() {
        LiveAgents.shared.end(workspace: url)
        let leaving = url.deletingLastPathComponent().appending(path: ".removing-\(UUID().uuidString)")
        guard (try? FileManager.default.moveItem(at: url, to: leaving)) != nil else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        Task.detached(priority: .background) { try? FileManager.default.removeItem(at: leaving) }
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

    /// What the workspaces hold on disk, for the diagnostics: counts and sizes, never names.
    nonisolated struct Usage: Equatable, Sendable {
        /// This process's workspaces.
        var folders = 0
        /// The files and folders in them, as `FileAttachment.folderLimit` counts them.
        var items = 0
        var bytes: Int64 = 0
        /// The most items in one workspace.
        var mostItems = 0
        /// The folders of other Meraline processes: one still running, or a process that took a gone one's id.
        var otherProcesses = 0
    }

    /// Walks every workspace of this process, so it can take a while; call it off the main thread.
    static func usage(in root: URL = defaultRoot, parent: URL = parent) -> Usage {
        var usage = Usage()
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        // A workspace being removed in the background is on its way out.
        for folder in folders where !folder.lastPathComponent.hasPrefix(".") {
            usage.folders += 1
            var items = 0
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
            if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) {
                for case let item as URL in enumerator {
                    items += 1
                    let values = try? item.resourceValues(forKeys: Set(keys))
                    if values?.isRegularFile == true { usage.bytes += Int64(values?.fileSize ?? 0) }
                }
            }
            usage.items += items
            usage.mostItems = max(usage.mostItems, items)
        }
        let others = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        usage.otherProcesses = others.filter { pid_t($0) != nil && $0 != root.lastPathComponent }.count
        return usage
    }
}
