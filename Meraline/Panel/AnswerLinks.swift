import AppKit
import SwiftUI

/// Paths and `meraline://` URLs in an answer, made into links as it is drawn. A click on a path opens the file
/// or folder by the rules a handed-over file's Open follows (`PresentedFile.Opening`), and ⌘-click shows it in
/// Finder; a `meraline://` link runs its route in this Meraline, without sending anything. Only a path to a file
/// or folder that is on this Mac becomes a link: absolute, from the home folder (`~/`), or, in an agent's chat,
/// inside its workspace. The links are found each time the answer is drawn and kept nowhere.
nonisolated enum AnswerLinks {
    /// Links the paths and `meraline://` URLs in `text`, and points a link the model wrote to a path, such as
    /// `[report](out/report.md)`, at the file. Code spans count, a whole span first, spaces and all; code
    /// blocks are left alone. `workspace` is what an agent's relative paths start from.
    static func linkify(_ text: inout AttributedString, workspace: URL?) {
        var checker = PathChecker(workspace: workspace)
        let characters = Array(text.characters)
        var links: [(range: Range<Int>, url: URL)] = []
        var segments: [(range: Range<Int>, isCode: Bool)] = []

        var offset = 0
        for run in text.runs {
            let range = offset..<offset + text[run.range].characters.count
            offset = range.upperBound
            if let link = run.link {
                if let file = checker.item(linkedAs: link) { links.append((range, file)) }
                continue
            }
            let isCode = run.inlinePresentationIntent?.contains(.code) == true
            // Bold or italic in the middle of a path doesn't cut it in two; code spans stand alone.
            if let last = segments.last, !isCode, !last.isCode, last.range.upperBound == range.lowerBound {
                segments[segments.count - 1].range = last.range.lowerBound..<range.upperBound
            } else {
                segments.append((range, isCode))
            }
        }

        for segment in segments {
            if segment.isCode, let whole = wholeSpan(characters, segment.range, checker: &checker) {
                links.append(whole)
            } else {
                links += words(characters, segment.range, checker: &checker)
            }
        }

        for link in links {
            let start = text.index(text.startIndex, offsetByCharacters: link.range.lowerBound)
            let end = text.index(start, offsetByCharacters: link.range.count)
            // As `MarkdownText` draws the links the model wrote.
            text[start..<end].link = link.url
            text[start..<end].foregroundColor = .primary
            text[start..<end].underlineStyle = .single
        }
    }

    /// A code span that is one path or `meraline://` URL, spaces and all, as agents write `` `~/My Notes/a.md` ``.
    private static func wholeSpan(_ characters: [Character], _ range: Range<Int>, checker: inout PathChecker) -> (Range<Int>, URL)? {
        var range = range
        while let first = range.first, characters[first].isWhitespace { range = range.dropFirst() }
        while let last = range.last, characters[last].isWhitespace { range = range.dropLast() }
        guard !range.isEmpty, let (length, url) = link(for: Array(characters[range]), checker: &checker) else { return nil }
        return (range.lowerBound..<range.lowerBound + length, url)
    }

    /// The links among the words in `range`: each word without the quotes or brackets before it, cut at the first
    /// character a path is never written with. An absolute path that isn't there takes in up to
    /// `wordsWithSpaces` more words, for folders such as Application Support.
    private static func words(_ characters: [Character], _ range: Range<Int>, checker: inout PathChecker) -> [(Range<Int>, URL)] {
        var words: [Range<Int>] = []
        var start: Int?
        for index in range {
            if characters[index].isWhitespace {
                if let begun = start { words.append(begun..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let begun = start { words.append(begun..<range.upperBound) }

        /// Where a word's token ends: at the first stop, or the word's end.
        func tokenEnd(_ word: Range<Int>, from start: Int) -> Int {
            characters[start..<word.upperBound].firstIndex { stops.contains($0) } ?? word.upperBound
        }

        var links: [(Range<Int>, URL)] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            index += 1
            let start = characters[word].firstIndex { !openers.contains($0) } ?? word.upperBound
            var end = tokenEnd(word, from: start)
            guard start < end else { continue }
            if let (length, url) = link(for: Array(characters[start..<end]), checker: &checker) {
                links.append((start..<start + length, url))
                continue
            }
            guard characters[start] == "/" || characters[start...].starts(with: "~/"), end == word.upperBound else { continue }
            var longest: (length: Int, url: URL, words: Int)?
            var next = index
            while next < words.count, next - index < wordsWithSpaces,
                  words[next].lowerBound == end + 1, characters[end] == " " {
                end = tokenEnd(words[next], from: words[next].lowerBound)
                if let (length, url) = link(for: Array(characters[start..<end]), checker: &checker) {
                    longest = (length, url, next + 1 - index)
                }
                guard end == words[next].upperBound else { break }
                next += 1
            }
            if let longest {
                links.append((start..<start + longest.length, longest.url))
                index += longest.words
            }
        }
        return links
    }

    /// The most words after the first that a path with spaces in it may take.
    static let wordsWithSpaces = 4

    /// Written before a path, as in (/tmp/a) or "~/b": not part of it.
    private static let openers: Set<Character> = ["(", "[", "{", "<", "\"", "'", "“", "‘", "«"]
    /// Never in a path as answers write one: a path ends at the first.
    private static let stops: Set<Character> = ["\"", "<", ">", "|", "`", "“", "”", "«", "»"]
    /// Written after a path, as in "saved to ~/a.txt.": not part of it.
    private static let closers: Set<Character> = [".", ",", ";", ":", "!", "?", "'", "’", "\"", "”", "»"]

    /// The link a token starts with, and how many of its characters the link takes: the token without the
    /// punctuation after it. Nil when the token is no path or URL, or names nothing on this Mac.
    private static func link(for token: [Character], checker: inout PathChecker) -> (Int, URL)? {
        let length = withoutClosers(token)
        guard length > 0 else { return nil }
        let text = String(token[..<length])
        let lowercased = text.lowercased()
        if lowercased.hasPrefix(AutomationRoute.scheme + "://") {
            guard let url = URL(string: text), AutomationRoute(url: url) != nil else { return nil }
            return (length, url)
        }
        if lowercased.hasPrefix("file://") {
            guard let url = URL(string: text), url.isFileURL, let item = checker.item(at: url.path(percentEncoded: false)) else { return nil }
            return (length, item)
        }
        guard let item = checker.item(named: text) ?? withoutLine(text).flatMap({ checker.item(named: $0) }) else { return nil }
        return (length, item)
    }

    /// How much of `token` is left without the punctuation that follows a path in a sentence, and without a
    /// closing bracket that has no opening one in it.
    private static func withoutClosers(_ token: [Character]) -> Int {
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{", ">": "<"]
        var end = token.count
        while end > 0 {
            let last = token[end - 1]
            if closers.contains(last) {
                end -= 1
            } else if let opening = pairs[last], token[..<end].count(where: { $0 == last }) > token[..<end].count(where: { $0 == opening }) {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    /// The path without the line, and column, that tools write after it: "Sources/App.swift:42:7" names
    /// Sources/App.swift. Nil when there is none.
    static func withoutLine(_ path: String) -> String? {
        var path = Substring(path)
        var found = false
        for _ in 0..<2 {
            guard let colon = path.lastIndex(of: ":") else { break }
            let number = path[path.index(after: colon)...]
            guard let first = number.first, first.isASCII, first.isNumber,
                  number.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }) else { break }
            path = path[..<colon]
            found = true
        }
        return found && !path.isEmpty ? String(path) : nil
    }

    // MARK: Opening

    /// A click on a link in an answer. A path opens by the rules of a handed-over file's Open, or shows in Finder
    /// with ⌘ held; a `meraline://` link runs its route without sending; any other link goes to its app.
    @MainActor
    static func open(_ url: URL) -> OpenURLAction.Result {
        if url.isFileURL {
            openItem(at: url, revealing: isCommandClick)
            return .handled
        }
        guard url.scheme?.lowercased() == AutomationRoute.scheme else { return .systemAction }
        guard AutomationRoute(url: url) != nil else {
            Log.panel.error("Ignored a link to an unknown meraline:// route")
            return .discarded
        }
        Log.panel.info("Following a meraline:// link in an answer")
        NSApp.delegate?.application?(NSApp, open: [AutomationRoute.withoutSending(url)])
        return .handled
    }

    /// Whether ⌘ was held for the click that followed the link. Selectable text follows it on the mouse's release,
    /// which is still the event at hand; followed another way, as VoiceOver does, it is ⌘ on the keyboard now.
    @MainActor private static var isCommandClick: Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown else {
            return NSEvent.modifierFlags.contains(.command)
        }
        return event.modifierFlags.contains(.command)
    }

    /// Opens the file or folder at `url` as a handed-over file's Open does, or shows it in Finder when it would
    /// run something or `revealing`. A file from a chat's workspace is marked as downloaded first, as a
    /// handed-over one is; anything else on the Mac is left as it is.
    @MainActor
    static func openItem(at url: URL, revealing: Bool) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            Log.panel.info("A path linked in an answer is gone")
            NSSound.beep()
            return
        }
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
        let opening = revealing ? .never : PresentedFile.opening(of: url, isFolder: isDirectory.boolValue && !isPackage)
        guard let app = PresentedFile.opener(for: url, opening: opening) else {
            Log.panel.info("Showing a path linked in an answer in Finder")
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        if ChatWorkspace.holds(url) { PresentedFile.markAsDownloaded(url) }
        Log.panel.info("Opening a path linked in an answer in \(PresentedFile.appName(app))")
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Log.panel.error("Couldn’t open a path linked in an answer: \(error.localizedDescription)") }
        }
    }

    // MARK: What is on this Mac

    /// Where file systems that a look can wait on are mounted: servers, which can keep it waiting for a minute
    /// when they went away, and autofs, whose places mount a server the moment they are looked at. Answers are
    /// drawn on the main thread, so paths there never become links.
    static func remoteMountPoints() -> [String] {
        // autofs's usual places, which other names can reach: /home is a link to one.
        var points = ["/net", "/Network", "/home"]
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return points }
        var mounts: [statfs] = Array(repeating: .init(), count: Int(count))
        let filled = mounts.withUnsafeMutableBufferPointer {
            getfsstat($0.baseAddress, Int32($0.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        for mount in mounts.prefix(Int(max(0, filled))) {
            let type = withUnsafeBytes(of: mount.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard mount.f_flags & UInt32(MNT_LOCAL) == 0 || type == "autofs" else { continue }
            points.append(withUnsafeBytes(of: mount.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
        }
        return points
    }

    /// Whether `path` is under one of `points`.
    static func isUnder(_ path: String, _ points: [String]) -> Bool {
        points.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Finds the files and folders paths name, for one drawing of an answer. The mounts are read once, and only
    /// when a word looks like a path.
    private struct PathChecker {
        let workspace: URL?
        private var remote: [String]?

        init(workspace: URL?) {
            self.workspace = workspace
        }

        /// The file or folder a path in an answer names: absolute, from `~/`, or relative to the workspace. A
        /// relative path needs a workspace and a slash or an extension, so plain words cost nothing.
        mutating func item(named path: String) -> URL? {
            if path.hasPrefix("/") {
                // "/" alone, or "//", is punctuation or a comment.
                guard path.count > 1, !path.hasPrefix("//") else { return nil }
                return item(at: path)
            }
            if path.hasPrefix("~/") {
                guard path.count > 2 else { return nil }
                return item(at: (path as NSString).expandingTildeInPath)
            }
            guard let workspace, let first = path.first, first.isLetter || first.isNumber || first == "_" || first == ".",
                  !path.contains("://"), path.contains("/") || !(path as NSString).pathExtension.isEmpty else { return nil }
            return item(at: workspace.appending(path: path).path)
        }

        /// A link the model wrote to a path rather than a web page, such as `[report](out/report.md#L3)`, or nil.
        mutating func item(linkedAs link: URL) -> URL? {
            if link.isFileURL { return item(at: link.path(percentEncoded: false)) }
            guard link.scheme == nil else { return nil }
            let path = link.path(percentEncoded: false)
            return path.isEmpty ? nil : item(named: path)
        }

        /// The file or folder at an absolute path, when it is one on a local disk.
        mutating func item(at path: String) -> URL? {
            guard path.utf8.count < Int(PATH_MAX) else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if remote == nil { remote = AnswerLinks.remoteMountPoints() }
            guard !AnswerLinks.isUnder(url.path, remote ?? []) else { return nil }
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            // Not a device, a socket, or a pipe.
            let type = info.st_mode & S_IFMT
            return type == S_IFREG || type == S_IFDIR ? url : nil
        }
    }
}

extension EnvironmentValues {
    /// The open chat's workspace, which an agent's relative paths in its answers start from; nil in an LLM's chat.
    @Entry var answerWorkspace: URL? = nil
}
