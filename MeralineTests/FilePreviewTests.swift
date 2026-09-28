import Foundation
import Network
import os
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import Meraline

@MainActor
struct FilePreviewTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "FilePreviewTests-\(UUID().uuidString)")

    private func write(_ text: String, to name: String) throws -> URL {
        let url = folder.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func pagesAndMarkdownArePreviewed() {
        func kind(_ pathExtension: String) -> FilePreview.Kind? {
            FilePreview.kind(of: UTType(filenameExtension: pathExtension), pathExtension: pathExtension)
        }
        #expect(kind("html") == .html)
        #expect(kind("HTM") == .html)
        #expect(kind("md") == .markdown)
        #expect(kind("markdown") == .markdown)
        #expect(FilePreview.kind(of: nil, pathExtension: "mdown") == .markdown, "an extension no app declares")
        #expect(kind("txt") == nil)
        #expect(kind("pdf") == nil)
        #expect(kind("png") == nil)
        #expect(kind("swift") == nil)
    }

    @Test func aPreviewIsReadFromTheFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(FilePreview.preview(at: try write("<h1>Hi</h1>", to: "page.html")) == .html)
        #expect(FilePreview.preview(at: try write("# Notes\n\nOne", to: "notes.md")) == .markdown("# Notes\n\nOne"))
        #expect(FilePreview.preview(at: try write(" \n\n", to: "empty.md")) == nil, "nothing to show")
        #expect(FilePreview.preview(at: try write("Plain", to: "plain.txt")) == nil)
        #expect(FilePreview.preview(at: folder.appending(path: "missing.md")) == nil)
    }

    @Test func markdownLeavesOutItsFrontMatter() {
        let file = "---\ntitle: Press kit\ndate: 2026-09-28\n---\n\n# Press kit\n\nSizes."
        #expect(FilePreview.markdown(in: Data(file.utf8), isCut: false) == "# Press kit\n\nSizes.")
        // A rule with no end to match is the file's own.
        let rule = "---\n\nText under a rule."
        #expect(FilePreview.markdown(in: Data(rule.utf8), isCut: false) == rule)
        #expect(FilePreview.markdown(in: Data("---\ntitle: Only\n---\n".utf8), isCut: false) == nil)
    }

    @Test func aLongFileIsReadToAWholeLine() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let line = String(repeating: "word ", count: 30) + "end"
        let url = try write(Array(repeating: line, count: 1_000).joined(separator: "\n"), to: "long.md")
        let text = try #require(FilePreview.markdown(at: url))
        #expect(text.hasSuffix("end"))
        #expect(text.utf8.count <= FilePreview.markdownByteLimit)
        #expect(Set(text.components(separatedBy: "\n")) == [line])

        let many = (1...500).map { "Line \($0)" }.joined(separator: "\n")
        let lines = try #require(FilePreview.markdown(in: Data(many.utf8), isCut: false)).components(separatedBy: "\n")
        #expect(lines.count == FilePreview.markdownLineLimit)
        #expect(lines.last == "Line \(FilePreview.markdownLineLimit)")
    }

    @Test func theStripShowsUpToItsHeightAndMoreOnceClicked() {
        #expect(FilePreviewStrip.shownHeight(of: nil, enlarged: false) == FilePreviewStrip.height, "a page still loading")
        #expect(FilePreviewStrip.shownHeight(of: 80, enlarged: false) == 80)
        #expect(FilePreviewStrip.shownHeight(of: 80, enlarged: true) == 80)
        #expect(FilePreviewStrip.shownHeight(of: 1_000, enlarged: false) == FilePreviewStrip.height)
        #expect(FilePreviewStrip.shownHeight(of: 1_000, enlarged: true) == FilePreviewStrip.enlargedHeight)
        #expect(FilePreviewStrip.shownHeight(of: .infinity, enlarged: true) == FilePreviewStrip.enlargedHeight, "a page not measured")
        #expect(!FilePreviewStrip.enlarges(nil))
        #expect(!FilePreviewStrip.enlarges(FilePreviewStrip.height))
        #expect(FilePreviewStrip.enlarges(FilePreviewStrip.height + 40))
    }

    @Test func aPageReadsFromTheChatsWorkspace() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try write("<p>Report</p>", to: "out/report.html")
        let file = try PresentedFile.resolve("out/report.html", in: folder)
        #expect(file.workspace.path == folder.resolvingSymlinksInPath().path)
    }

    /// Loads `page` in `view` and waits for `loader` to measure it: its height, nil when it wasn't measured, or
    /// .none when it didn't load in time.
    private func load(_ page: URL, in view: WKWebView, with loader: PagePreview.Loader) async -> CGFloat?? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let finish: (CGFloat??) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
            loader.measured = { finish($0) }
            loader.failed = { finish(nil) }
            Task { try? await Task.sleep(for: .seconds(15)); finish(nil) }
            view.loadFileURL(page, allowingReadAccessTo: folder)
        }
    }

    /// A page is measured with its scripts off, and a refresh doesn't take the preview anywhere else.
    @Test func aPageLoadsAloneWithoutItsScripts() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = try write("""
            <!doctype html>
            <html><head><meta http-equiv="refresh" content="0; url=other.html"><style>body { margin: 0 }</style></head>
            <body><div style="height: 500px"></div><img src="https://example.com/pixel.png" style="position: absolute; top: 0">
            <script>document.body.style.height = '3000px'</script></body></html>
            """, to: "page.html")
        _ = try write("<p>Somewhere else</p>", to: "other.html")
        let rules = try #require(await FilePreview.offlineRules())
        let loader = PagePreview.Loader(url: page)
        let view = PagePreview.makeWebView(rules: rules, loader: loader)
        #expect(await load(page, in: view, with: loader) == 500 * FilePreview.pageZoom)
        try await Task.sleep(for: .milliseconds(600))
        #expect(view.url?.lastPathComponent == "page.html")
    }

    /// A page's pictures and styles come from the workspace, and nothing it names on a server is asked for: a
    /// server on this Mac hears from a web view without the preview's rules, and never from the preview.
    @Test func aPageAsksNothingOfTheNetwork() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try await Doorbell()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #require(Data(base64Encoded: Self.pixel)).write(to: folder.appending(path: "dot.png"))
        let page = try write("""
            <!doctype html>
            <html><head><link rel="stylesheet" href="http://127.0.0.1:\(server.port)/style.css"></head>
            <body><img id="local" src="dot.png"><img src="http://127.0.0.1:\(server.port)/pixel.png"></body></html>
            """, to: "page.html")
        let rules = try #require(await FilePreview.offlineRules())
        let loader = PagePreview.Loader(url: page)
        let view = PagePreview.makeWebView(rules: rules, loader: loader)
        let measured = await load(page, in: view, with: loader)
        #expect(measured != nil, "the page loaded")
        let width = try await view.evaluateJavaScript("document.getElementById('local').naturalWidth") as? Int
        #expect(width == 1, "the workspace's picture")
        try await Task.sleep(for: .milliseconds(800))
        #expect(server.rings == 0)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let plain = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), configuration: configuration)
        plain.loadFileURL(page, allowingReadAccessTo: folder)
        for _ in 0..<50 where server.rings == 0 { try await Task.sleep(for: .milliseconds(100)) }
        #expect(server.rings > 0, "the server can be reached, so the preview's silence counts")
    }

    /// A PNG of one pixel.
    private static let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
}

/// A server on this Mac that answers nothing and counts who called.
nonisolated private final class Doorbell: Sendable {
    private let listener: NWListener
    private let count = OSAllocatedUnfairLock(initialState: 0)
    let port: UInt16

    var rings: Int { count.withLock { $0 } }

    init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let count = count
        listener.newConnectionHandler = { connection in
            count.withLock { $0 += 1 }
            connection.cancel()
        }
        self.listener = listener
        port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                let value: Result<UInt16, Error>? = switch state {
                case .ready: .success(listener.port?.rawValue ?? 0)
                case .failed(let error): .failure(error)
                default: nil
                }
                guard let value, !resumed.withLock({ let was = $0; $0 = true; return was }) else { return }
                continuation.resume(with: value)
            }
            listener.start(queue: .global())
        }
    }

    deinit {
        listener.cancel()
    }
}
