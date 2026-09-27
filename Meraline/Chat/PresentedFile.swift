import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// A file or folder an agent handed over with `present_files` (see `PresentFilesServer`), shown under its answer
/// as a card you can open, show in Finder, copy, save to Downloads, or drag out. It stays where the agent made it,
/// in the chat's workspace, and goes with the workspace; only what you copy or save elsewhere outlives the chat.
nonisolated struct PresentedFile: Identifiable, Equatable, Sendable {
    /// The most files one call hands over. A longer list is turned away whole, and the agent is told to send an
    /// archive instead.
    static let limit = 20

    /// Where it is, symlinks resolved, inside the chat's workspace.
    let url: URL
    /// Its path inside the workspace, as the agent would name it: "report.pdf", "out/chart.png".
    let path: String
    /// A folder, as opposed to a file or a package such as a Keynote document.
    let isFolder: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// Why a path can't be handed over, in words for the agent that sent it.
    enum Problem: Error, Equatable {
        case missing(String)
        case outside(String)
        case workspace

        var message: String {
            switch self {
            case .missing(let path): "There is no file at “\(path)”."
            case .outside(let path): "“\(path)” is outside the working directory. Copy it into the working directory, then hand over the copy."
            case .workspace: "That is the working directory itself. Hand over the files in it."
            }
        }
    }

    /// The file `path` names: relative to `workspace`, or absolute inside it. Symlinks are followed first, so a
    /// link can't reach out of the workspace.
    static func resolve(_ path: String, in workspace: URL) throws(Problem) -> PresentedFile {
        let given = (path.trimmed as NSString).expandingTildeInPath
        guard !given.isEmpty else { throw .missing(path) }
        let root = workspace.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = given.hasPrefix("/") ? URL(fileURLWithPath: given) : workspace.appending(path: given)
        let url = resolved(candidate)
        if url.path == root { throw .workspace }
        guard url.path.hasPrefix(root + "/") else { throw .outside(path) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw .missing(path) }
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
        return PresentedFile(url: url, path: String(url.path.dropFirst(root.count + 1)), isFolder: isDirectory.boolValue && !isPackage)
    }

    /// `url` with every symlink in it followed, even when its last parts don't exist: `resolvingSymlinksInPath()`
    /// leaves a path that doesn't exist as it is, so a missing file behind a link out of the workspace would seem
    /// to be inside it. The part that exists is resolved, and the rest goes on the end.
    private static func resolved(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        guard standardized.path != "/", !FileManager.default.fileExists(atPath: standardized.path) else {
            return standardized.resolvingSymlinksInPath()
        }
        return resolved(standardized.deletingLastPathComponent()).appending(path: standardized.lastPathComponent)
    }

    /// The files `paths` name inside `workspace`, each once, and what is wrong with the others. Meraline's MCP
    /// server answers the agent with it and the panel reads the same call with it, so the panel shows exactly the
    /// files the agent was told it handed over.
    static func handOver(_ paths: [String], in workspace: URL) -> (files: [PresentedFile], problems: [String]) {
        guard !paths.isEmpty else { return ([], ["Name at least one file in filepaths."]) }
        guard paths.count <= limit else {
            return ([], ["That is \(paths.count) files; hand over at most \(limit) at once. Put the rest in a zip archive and hand that over."])
        }
        var files: [PresentedFile] = []
        var problems: [String] = []
        for path in paths {
            do {
                let file = try resolve(path, in: workspace)
                if !files.contains(where: { $0.id == file.id }) { files.append(file) }
            } catch {
                problems.append(error.message)
            }
        }
        return (files, problems)
    }

    /// How Open treats a file.
    enum Opening: Equatable {
        /// In the app the Mac opens it with, as a double-click in Finder would.
        case inDefaultApp
        /// In the app the Mac opens plain text with: a script, whose own app might run it.
        case asText
        /// Not at all: an app, a program, or a file that runs or installs something when opened. Show in Finder
        /// still reaches it, for you to open knowingly.
        case never
    }

    /// Kinds that do something beyond showing themselves when opened: Terminal settings run a command, the
    /// rest install or run what is in them.
    private static let runsWhenOpened: Set<String> = ["terminal", "workflow", "fileloc", "mobileconfig", "shortcut", "prefpane", "saver"]

    /// How Open treats a file of `type`, `isExecutable` when it is a plain file anyone may run.
    static func opening(for type: UTType?, pathExtension: String, isExecutable: Bool) -> Opening {
        if runsWhenOpened.contains(pathExtension.lowercased()) { return .never }
        guard let type else { return isExecutable ? .never : .inDefaultApp }
        if type.conforms(to: .application) { return .never }
        // Before programs: JavaScript is both.
        if type.conforms(to: .script) { return .asText }
        if type.conforms(to: .executable) || type.conforms(to: .applicationExtension) { return .never }
        if isExecutable && !type.conforms(to: .text) { return .never }
        return .inDefaultApp
    }

    var opening: Opening {
        if isFolder { return .inDefaultApp }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let isExecutable = values?.isRegularFile == true && FileManager.default.isExecutableFile(atPath: url.path)
        return Self.opening(for: type, pathExtension: url.pathExtension, isExecutable: isExecutable)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// The app Open uses, or nil when it would use none.
    @MainActor var opener: URL? {
        switch opening {
        case .inDefaultApp: NSWorkspace.shared.urlForApplication(toOpen: url)
        case .asText: NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        case .never: nil
        }
    }

    /// What Finder calls the file and how big it is: "PDF document · 240 KB", or "Folder". A folder or a package,
    /// such as an app, goes without a size, which would take adding up everything in it.
    var summary: String {
        let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
            ?? (isFolder ? "Folder" : "File")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType != .typeDirectory,
              let size = attributes[.size] as? Int64 else { return kind }
        return "\(kind) · \(size.formatted(.byteCount(style: .file)))"
    }

    /// Marks the file as downloaded, as a browser marks what it saves, before it goes to another app: an app or a
    /// program in it then has to pass macOS's checks before it first runs, the way anything from the internet
    /// does, since what an agent makes may come from a page it read. A mark already there stays as it is.
    func markAsDownloaded() {
        guard (try? url.resourceValues(forKeys: [.quarantinePropertiesKey]))?.quarantineProperties == nil else { return }
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
            kLSQuarantineAgentNameKey as String: "Meraline"
        ]
        var url = url
        do {
            try url.setResourceValues(values)
        } catch {
            Log.chat.error("Couldn’t mark a handed-over file as downloaded: \(error.localizedDescription)")
        }
    }

    /// An app's name as Finder shows it, without ".app".
    static func appName(_ app: URL) -> String {
        (FileManager.default.displayName(atPath: app.path) as NSString).deletingPathExtension
    }

    /// Whether the file is a picture its card can show, by its type.
    var isImage: Bool { !isFolder && ImageAttachment.isImage(at: url) }

    /// The picture its card shows: at most `maximumPixelSize` on its longer side, never larger than the file's
    /// own, and turned upright as its orientation says. Nil when ImageIO can't read it. It is read off the main
    /// thread and lives only in the card.
    static func picture(at url: URL, maximumPixelSize: Int = 1_200) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// What is done with the files an agent handed over: open, show in Finder, copy, save to Downloads. The card under
/// the answer, the chat's actions, and their shortcuts all come here, so the card says for a moment what was done
/// with its file wherever it was done.
@Observable
final class PresentedFiles {
    static let shared = PresentedFiles()

    /// What was just done with a file, said on its card for a moment.
    enum Notice: Equatable {
        case copied
        case saving
        /// Saved to Downloads, under this name.
        case saved(String)
        case failed(String)
        /// The file left the workspace since it was handed over.
        case gone
    }

    private(set) var notices: [PresentedFile.ID: Notice] = [:]
    @ObservationIgnored private var clearing: [PresentedFile.ID: Task<Void, Never>] = [:]

    /// Opens the file in the app Open uses. Opening a folder shows it in Finder.
    func open(_ file: PresentedFile) {
        guard present([file]) == [file], let app = file.opener else { return }
        file.markAsDownloaded()
        Log.chat.info("Opening a handed-over file in \(PresentedFile.appName(app))")
        NSWorkspace.shared.open([file.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Log.chat.error("Couldn’t open a handed-over file: \(error.localizedDescription)") }
        }
    }

    func showInFinder(_ files: [PresentedFile]) {
        let files = present(files)
        guard !files.isEmpty else { return }
        Log.chat.info("Showing \(files.count) handed-over file(s) in Finder")
        NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url))
    }

    /// Puts the files on the clipboard as Finder's Copy does, to paste into Finder, Mail, or a chat.
    func copy(_ files: [PresentedFile]) {
        let files = present(files)
        guard !files.isEmpty else { return }
        files.forEach { $0.markAsDownloaded() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(files.map { $0.url as NSURL })
        Log.chat.info("Copied \(files.count) handed-over file(s)")
        for file in files { say(.copied, about: file) }
    }

    /// Copies the files into Downloads, numbered when a name is taken there, so they outlive the chat. The copying
    /// happens off the main thread: a folder can be large, and the first save may wait on macOS asking for access
    /// to Downloads.
    func saveToDownloads(_ files: [PresentedFile]) {
        let files = present(files)
        guard !files.isEmpty else { return }
        files.forEach { $0.markAsDownloaded() }
        for file in files { say(.saving, about: file, fades: false) }
        Task {
            let results = await Task.detached(priority: .userInitiated) { Self.copyToDownloads(files) }.value
            for (file, result) in zip(files, results) {
                switch result {
                case .success(let name): say(.saved(name), about: file)
                case .failure(let error): say(.failed(error.localizedDescription), about: file)
                }
            }
            let saved = results.filter { if case .success = $0 { true } else { false } }.count
            Log.chat.info("Saved \(saved) of \(files.count) handed-over file(s) to Downloads")
        }
    }

    nonisolated private static func copyToDownloads(_ files: [PresentedFile]) -> [Result<String, Error>] {
        do {
            let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return copy(files, into: downloads)
        } catch {
            return files.map { _ in .failure(error) }
        }
    }

    /// Copies the files into `folder`, each under its own name or, when that is taken there, a numbered one, and
    /// says which name each got.
    nonisolated static func copy(_ files: [PresentedFile], into folder: URL) -> [Result<String, Error>] {
        let manager = FileManager.default
        var taken = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.map { file in
            let name = FileAttachment.uniqueName(for: file.name, splittingExtension: !file.isFolder, avoiding: taken)
            do {
                try manager.copyItem(at: file.url, to: folder.appending(path: name))
                taken.append(name)
                return .success(name)
            } catch {
                return .failure(error)
            }
        }
    }

    func notice(for file: PresentedFile) -> Notice? {
        notices[file.id]
    }

    /// The files still in the workspace; the cards of the others say they are gone.
    private func present(_ files: [PresentedFile]) -> [PresentedFile] {
        let (present, gone) = (files.filter(\.exists), files.filter { !$0.exists })
        for file in gone { say(.gone, about: file) }
        return present
    }

    /// Says `notice` on the file's card, for a moment unless it doesn't `fade`, like Saving… which the result replaces.
    private func say(_ notice: Notice, about file: PresentedFile, fades: Bool = true) {
        notices[file.id] = notice
        clearing[file.id]?.cancel()
        guard fades else { return }
        clearing[file.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(notice == .copied ? 1.5 : 4))
            guard !Task.isCancelled else { return }
            self?.notices[file.id] = nil
        }
    }
}
