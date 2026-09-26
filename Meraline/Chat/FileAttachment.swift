import Foundation

/// A file or a folder for an agent: a PDF, a spreadsheet, a project, anything that isn't an image. Only agents
/// take them, so in LLM mode the panel asks you to switch to Agent first. The draft keeps only where it is;
/// sending the question copies it into the chat's workspace under `name`, and the prompt tells the agent it is
/// there. The copy stays with the workspace, so later questions can come back to it, and whatever the agent
/// changes, it changes in the copy.
nonisolated struct FileAttachment: Identifiable, Equatable, Sendable {
    /// The most files a folder brings along. More would keep the question waiting on the copy.
    static let folderLimit = 20_000

    let id = UUID()
    /// Where the file is on this Mac.
    let url: URL
    /// Its name in the workspace: the file's own, numbered when the chat has something by that name already.
    let name: String
    /// A folder, as opposed to a file or a package such as a Keynote document.
    let isFolder: Bool

    /// The file or folder at `url`, named so it takes none of the names in `taken`. A whole disk or the home
    /// folder is turned away: it is never what "ask this project" means, and reading it would be slow and
    /// ask for access to every protected folder in it.
    static func make(from url: URL, avoiding taken: [String]) throws -> FileAttachment {
        let url = url.resolvingSymlinksInPath()
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw AttachmentError.unreadableFile }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isVolumeKey])
        if values?.isVolume == true || url.path == FileManager.default.homeDirectoryForCurrentUser.path {
            throw AttachmentError.tooManyFiles(url.lastPathComponent)
        }
        let isFolder = values?.isDirectory == true && values?.isPackage != true
        let name = uniqueName(for: url.lastPathComponent, splittingExtension: !isFolder, avoiding: taken)
        return FileAttachment(url: url, name: name, isFolder: isFolder)
    }

    /// What the attachments are, by format rather than name, for a line that reads well however long the
    /// names: "PDF files", "PDF and CSV files", "PDF files and folders", "folders". A file without an
    /// extension, or more than three formats, make it "these files".
    static func kinds(of files: [FileAttachment]) -> String {
        var formats: [String] = []
        for file in files where !file.isFolder {
            let format = (file.name as NSString).pathExtension.uppercased()
            if format.isEmpty { return "these files" }
            if !formats.contains(format) { formats.append(format) }
        }
        guard formats.count <= 3 else { return "these files" }
        let hasFolders = files.contains(where: \.isFolder)
        guard !formats.isEmpty else { return "folders" }
        let listed = formats.count > 2
            ? formats.dropLast().joined(separator: ", ") + ", and " + formats.last!
            : formats.joined(separator: " and ")
        return "\(listed) files\(hasFolders ? " and folders" : "")"
    }

    /// `name`, or `name 2`, `name 3`, and so on, before the extension of a file: the first that isn't taken.
    /// Names are compared the way the Mac's disk compares them, ignoring case.
    static func uniqueName(for name: String, splittingExtension: Bool = true, avoiding taken: [String]) -> String {
        let taken = Set(taken.map { $0.lowercased() })
        let pathExtension = splittingExtension ? (name as NSString).pathExtension : ""
        let base = pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        var candidate = name
        var number = 1
        while taken.contains(candidate.lowercased()) {
            number += 1
            candidate = pathExtension.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(pathExtension)"
        }
        return candidate
    }

    /// Copies each attachment into `folder` under its name, replacing whatever has that name there, as a
    /// question sent again after a failure finds its own copy from the first try.
    static func copy(_ files: [FileAttachment], into folder: URL, limit: Int = folderLimit) async throws {
        for file in files {
            let destination = folder.appending(path: file.name)
            try? FileManager.default.removeItem(at: destination)
            if file.isFolder {
                try await copyFolder(file, to: destination, limit: limit)
            } else {
                try FileManager.default.copyItem(at: file.url, to: destination)
            }
        }
    }

    /// A folder in a git repository brings the files git keeps or would keep, and the history when it is the
    /// repository's top, but not what git ignores, which in a project is mostly dependencies and builds. Any
    /// other folder comes whole. On the Mac's own disk each copy is a clone, which takes no space until changed.
    private static func copyFolder(_ file: FileAttachment, to destination: URL, limit: Int) async throws {
        let source = file.url
        guard let paths = try await pathsGitKeeps(in: source), !paths.isEmpty else {
            guard count(in: source, upTo: limit) <= limit else { throw AttachmentError.tooManyFiles(file.name) }
            try FileManager.default.copyItem(at: source, to: destination)
            Log.commandLine.info("Copied a folder outside git")
            return
        }
        guard paths.count <= limit else { throw AttachmentError.tooManyFiles(file.name) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for path in paths {
            try Task.checkCancellation()
            let item = source.appending(path: path)
            // Git still lists a file deleted since the last commit.
            guard (try? item.checkResourceIsReachable()) == true else { continue }
            let copy = destination.appending(path: path)
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: item, to: copy)
        }
        // Only a repository's own .git folder; a worktree's .git is a file that points back at the original.
        let history = source.appending(path: ".git")
        let hasHistory = (try? history.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if hasHistory { try FileManager.default.copyItem(at: history, to: destination.appending(path: ".git")) }
        Log.commandLine.info("Copied a folder of \(paths.count) file(s) git keeps\(hasHistory ? ", with its history" : "")")
    }

    /// The paths under `folder` that git tracks or would track, or nil when the folder isn't in a repository
    /// or git can't say. Git is asked only where there is a repository, because without Apple's developer
    /// tools the git in /usr/bin offers to install them instead of answering.
    private static func pathsGitKeeps(in folder: URL) async throws -> [String]? {
        guard isInRepository(folder), let git = CommandLineClient.resolve("git") else { return nil }
        let listing = try? await CommandLineClient.output(
            of: git,
            arguments: ["-C", folder.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            timeout: .seconds(60)
        )
        try Task.checkCancellation()
        guard let listing else {
            Log.commandLine.error("git couldn’t list a folder, so it is copied whole")
            return nil
        }
        // A file with a merge conflict is listed once for each side.
        return Array(Set(listing.split(separator: "\0").map(String.init))).sorted()
    }

    private static func isInRepository(_ folder: URL) -> Bool {
        var path = folder.path
        while true {
            if FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) { return true }
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty { return false }
            path = parent
        }
    }

    /// How many files and folders are under `folder`, counting no further than one past `limit`.
    private static func count(in folder: URL, upTo limit: Int) -> Int {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        while count <= limit, items.nextObject() != nil { count += 1 }
        return count
    }
}
