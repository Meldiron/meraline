import Foundation
import Testing
@testable import Meraline

@MainActor
struct AnswerLinksTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.links.\(UUID().uuidString)")

    /// A folder with report.md, My Notes/plan.md, and Sources/App.swift, its path as the tests write it.
    private func folder() throws -> String {
        let url = root.appending(path: "work")
        try FileManager.default.createDirectory(at: url.appending(path: "My Notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appending(path: "Sources"), withIntermediateDirectories: true)
        try Data("# Report".utf8).write(to: url.appending(path: "report.md"))
        try Data("plan".utf8).write(to: url.appending(path: "My Notes/plan.md"))
        try Data("let x = 1".utf8).write(to: url.appending(path: "Sources/App.swift"))
        return url.path
    }

    /// The links in `markdown` as an answer draws it: each linked stretch of text, and where it leads.
    private func links(in markdown: String, workspace: String? = nil) -> [Link] {
        var text = MarkdownText.render(markdown)
        AnswerLinks.linkify(&text, workspace: workspace.map { URL(fileURLWithPath: $0) })
        return text.runs.compactMap { run in run.link.map { Link(String(text[run.range].characters), $0) } }
    }

    private struct Link: Equatable, CustomStringConvertible {
        let text: String
        let url: URL

        init(_ text: String, _ url: URL) {
            self.text = text
            self.url = url
        }

        /// A file by its path, which a folder's URL spells with a slash at the end or without.
        private var target: String { url.isFileURL ? url.path : url.absoluteString }

        static func == (a: Link, b: Link) -> Bool {
            a.text == b.text && a.target == b.target
        }

        /// A link to a file, as the tests name it.
        static func file(_ text: String, _ path: String) -> Link {
            Link(text, URL(fileURLWithPath: path))
        }

        var description: String { "\(text) → \(url.absoluteString)" }
    }

    // MARK: Paths

    @Test func absolutePathsThatExistBecomeLinks() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(links(in: "Saved to \(folder)/report.md.") == [.file("\(folder)/report.md", "\(folder)/report.md")])
        #expect(links(in: "It's in \(folder)/Sources/") == [.file("\(folder)/Sources/", "\(folder)/Sources")])
        #expect(links(in: "Saved to \(folder)/missing.md.").isEmpty)
    }

    @Test func punctuationAroundAPathStaysOutOfTheLink() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = Link.file("\(folder)/report.md", "\(folder)/report.md")
        #expect(links(in: "(see \(folder)/report.md)") == [report])
        #expect(links(in: "“\(folder)/report.md”, then") == [report])
        #expect(links(in: "'\(folder)/report.md'?") == [report])
        #expect(links(in: "[\(folder)/report.md]") == [report])
    }

    @Test func wordsThatOnlyLookLikePathsStayText() {
        #expect(links(in: "Use A / B, and/or 1/2, or type /help and // comment.").isEmpty)
        // It is there, but it's a device, not a file or folder.
        #expect(links(in: "Send it to /dev/null.").isEmpty)
        #expect(links(in: "It weighs 3 km/h and costs $5/month.").isEmpty)
    }

    @Test func aPathWithSpacesTakesTheWordsAfterIt() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(links(in: "Open \(folder)/My Notes/plan.md to read it.") == [.file("\(folder)/My Notes/plan.md", "\(folder)/My Notes/plan.md")])
        #expect(links(in: "\(folder)/My Notes is a folder") == [.file("\(folder)/My Notes", "\(folder)/My Notes")])
    }

    @Test func aCodeSpanCountsWholeOrWordByWord() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(links(in: "Open `\(folder)/My Notes/plan.md`") == [.file("\(folder)/My Notes/plan.md", "\(folder)/My Notes/plan.md")])
        #expect(links(in: "Run `cat \(folder)/report.md` first") == [.file("\(folder)/report.md", "\(folder)/report.md")])
    }

    @Test func aLineNumberStaysInTheLinkButNotInThePath() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(links(in: "The error is at \(folder)/Sources/App.swift:42:7.") == [.file("\(folder)/Sources/App.swift:42:7", "\(folder)/Sources/App.swift")])
        #expect(AnswerLinks.withoutLine("App.swift:42") == "App.swift")
        #expect(AnswerLinks.withoutLine("App.swift:10-20") == "App.swift")
        #expect(AnswerLinks.withoutLine("App.swift") == nil)
        #expect(AnswerLinks.withoutLine("App.swift:main") == nil)
    }

    @Test func relativePathsNeedTheWorkspace() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let answer = "I changed Sources/App.swift and ./report.md, not Sources or README.md."
        #expect(links(in: answer, workspace: folder) == [
            .file("Sources/App.swift", "\(folder)/Sources/App.swift"),
            .file("./report.md", "\(folder)/report.md"),
        ])
        #expect(links(in: answer).isEmpty)
    }

    @Test func pathsFromTheHomeFolder() {
        #expect(links(in: "Look in ~/Library.") == [.file("~/Library", NSHomeDirectory() + "/Library")])
        #expect(links(in: "Just ~/ or ~").isEmpty)
    }

    @Test func fileURLsBecomeLinks() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = URL(fileURLWithPath: "\(folder)/My Notes/plan.md").absoluteString
        #expect(links(in: "See \(url).") == [.file(url, "\(folder)/My Notes/plan.md")])
    }

    @Test func linksTheModelWroteToPathsLeadToTheFiles() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(links(in: "Read [the report](report.md#L2).", workspace: folder) == [.file("the report", "\(folder)/report.md")])
        #expect(links(in: "Read [the report](\(folder)/report.md).") == [.file("the report", "\(folder)/report.md")])
        // Without a workspace, or to a web page, they stay as they were.
        #expect(links(in: "Read [the report](report.md).").map(\.url.absoluteString) == ["report.md"])
        #expect(links(in: "See [Apple](https://apple.com/report.md).", workspace: folder).map(\.url.absoluteString) == ["https://apple.com/report.md"])
    }

    @Test func nothingIsCheckedOnServers() {
        let points = AnswerLinks.remoteMountPoints()
        #expect(points.contains("/net"))
        #expect(points.contains("/home"))
        #expect(AnswerLinks.isUnder("/net/server/share", ["/net"]))
        #expect(AnswerLinks.isUnder("/Volumes/NAS", ["/Volumes/NAS"]))
        #expect(!AnswerLinks.isUnder("/network/x", ["/net"]))
        #expect(!AnswerLinks.isUnder("/Volumes/NASA", ["/Volumes/NAS"]))
    }

    // MARK: meraline://

    @Test func meralineURLsWithARouteBecomeLinks() {
        #expect(links(in: "Try meraline://play?game=odd-one-out.") == [Link("meraline://play?game=odd-one-out", URL(string: "meraline://play?game=odd-one-out")!)])
        #expect(links(in: "Or `meraline://settings?pane=usage`") == [Link("meraline://settings?pane=usage", URL(string: "meraline://settings?pane=usage")!)])
        #expect(links(in: "Not meraline://nowhere").isEmpty)
    }

    @Test func aLinkInAnAnswerNeverSends() throws {
        let url = AutomationRoute.withoutSending(URL(string: "meraline://ask?text=What%20is%20it%3F&SEND=1&agent=1")!)
        #expect(url.absoluteString == "meraline://ask?text=What%20is%20it%3F&agent=1")
        #expect(AutomationRoute(url: url) == .ask(text: "What is it?", mode: .agent, send: false))
        #expect(AutomationRoute.withoutSending(URL(string: "meraline://ask?send=1")!).absoluteString == "meraline://ask")
        #expect(AutomationRoute.withoutSending(URL(string: "meraline://play?game=a%26b")!).absoluteString == "meraline://play?game=a%26b")
    }

    // MARK: Opening

    @Test func workspacesAreKnownWherever() throws {
        let workspace = try ChatWorkspace.make(in: root.appending(path: "1234")).url
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Report".utf8).write(to: workspace.appending(path: "report.md"))
        #expect(ChatWorkspace.holds(workspace.appending(path: "report.md"), parent: root))
        // Spelled with /private, as the temporary folder really is.
        #expect(ChatWorkspace.holds(URL(fileURLWithPath: "/private" + workspace.path + "/report.md"), parent: root))
        #expect(!ChatWorkspace.holds(root, parent: root))
        #expect(!ChatWorkspace.holds(URL(fileURLWithPath: NSHomeDirectory()), parent: root))
    }

    @Test func linkedPathsOpenByTheRulesOfHandedOverFiles() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PresentedFile.opening(of: URL(fileURLWithPath: "\(folder)/report.md"), isFolder: false) == .inDefaultApp)
        #expect(PresentedFile.opening(of: URL(fileURLWithPath: "\(folder)/Sources"), isFolder: true) == .inDefaultApp)
        #expect(PresentedFile.opening(of: URL(fileURLWithPath: "/System/Applications/Calculator.app"), isFolder: false) == .never)
    }
}
