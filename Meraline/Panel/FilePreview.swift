import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// What the card of a handed-over page or Markdown file shows above its name, before you open or save it: HTML as a
/// browser draws it, and the start of a Markdown file drawn as an answer is. Any other file shows its icon, or its
/// picture (`PresentedFile.picture(at:)`).
nonisolated enum FilePreview: Equatable, Sendable {
    /// A page, drawn by WebKit with its scripts off and nothing loaded from anywhere but the chat's workspace.
    case html
    /// A Markdown file's first lines, front matter left out.
    case markdown(String)

    enum Kind: Equatable, Sendable {
        case html
        case markdown
    }

    /// How much of a Markdown file is read: far more than the strip shows, even enlarged, so it never ends early.
    static let markdownByteLimit = 16 * 1_024
    static let markdownLineLimit = 200

    private static let htmlExtensions: Set<String> = ["html", "htm"]
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]
    private static let markdownType = UTType("net.daringfireball.markdown")

    /// Which preview a file of `type` gets, by its type or, for a type no app on this Mac declares, its extension.
    static func kind(of type: UTType?, pathExtension: String) -> Kind? {
        let pathExtension = pathExtension.lowercased()
        if type?.conforms(to: .html) == true || htmlExtensions.contains(pathExtension) { return .html }
        if let markdownType, type?.conforms(to: markdownType) == true { return .markdown }
        return markdownExtensions.contains(pathExtension) ? .markdown : nil
    }

    /// The preview of the file at `url`, or nil when it gets none: not a page or Markdown, or Markdown with nothing
    /// in it. It reads the file, so it runs off the main thread.
    static func preview(at url: URL) -> FilePreview? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        switch kind(of: type, pathExtension: url.pathExtension) {
        case .html?: return .html
        case .markdown?: return markdown(at: url).map(FilePreview.markdown)
        case nil: return nil
        }
    }

    /// The start of the Markdown file at `url`, as `markdown(in:isCut:)` reads it.
    static func markdown(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: markdownByteLimit + 1) else { return nil }
        return markdown(in: data.prefix(markdownByteLimit), isCut: data.count > markdownByteLimit)
    }

    /// Markdown's first `markdownLineLimit` lines, without the front matter (the `---` block of settings some tools
    /// start a file with) and, when the file went on past what was read, `isCut`, without the line cut in two.
    /// Nil when that leaves nothing to show.
    static func markdown(in data: Data, isCut: Bool) -> String? {
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if isCut, lines.count > 1 { lines.removeLast() }
        if lines.first?.trimmed == "---",
           let end = lines.prefix(60).indices.dropFirst().first(where: { ["---", "..."].contains(lines[$0].trimmed) }) {
            lines.removeFirst(end + 1)
        }
        let text = lines.prefix(markdownLineLimit).joined(separator: "\n").trimmed
        return text.isEmpty ? nil : text
    }
}

extension PresentedFile {
    /// The chat's workspace, which the file's page may take its pictures and styles from.
    nonisolated var workspace: URL {
        URL(filePath: String(url.path.dropLast(path.count + 1)), directoryHint: .isDirectory)
    }
}

/// The preview of a page or a Markdown file, in a glass strip above its name on its card. It shows the top of the
/// file, fading out where it goes on, and a click shows more, up to `enlargedHeight`, inside the window as a
/// picture does. It is only to look at: clicks, keys, and scrolling go past it, and Open shows the whole file.
struct FilePreviewStrip: View {
    /// How tall the strip is at most, and once clicked.
    static let height: CGFloat = 160
    static let enlargedHeight: CGFloat = PresentedFileCard.enlargedPictureHeight
    /// How much of the strip's bottom fades out when the file goes on past it.
    static let fade: CGFloat = 28
    static let cornerRadius: CGFloat = 10

    let file: PresentedFile
    let preview: FilePreview
    /// Says the page can't be shown, for the card to show the file's icon instead.
    var failed: () -> Void = {}

    /// How tall the whole preview is; nil until a page has loaded, and infinite when it couldn't be measured.
    @State private var contentHeight: CGFloat?
    @State private var isEnlarged = false
    /// Whether the strip has been scrolled into view: a page loads only then, since each one runs WebKit.
    @State private var hasShown = false
    @State private var rules: WKContentRuleList?

    var body: some View {
        let enlarges = Self.enlarges(contentHeight)
        let height = Self.shownHeight(of: contentHeight, enlarged: isEnlarged && enlarges)
        Button {
            guard enlarges else { return }
            withAnimation(.smooth(duration: 0.25)) { isEnlarged.toggle() }
        } label: {
            content(height: height)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: height, alignment: .top)
                .clipShape(.rect(cornerRadius: Self.cornerRadius))
                .mask { fadeOut(height: height, cuts: (contentHeight ?? 0) > height + 1) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.separator) }
                .overlay { Color.clear.contentShape(.rect(cornerRadius: Self.cornerRadius)) }
        }
        .buttonStyle(.plain)
        .help(enlarges ? (isEnlarged ? "Show less" : "Show more") : file.name)
        .accessibilityLabel("Preview of \(file.name)")
        .accessibilityHint(enlarges ? (isEnlarged ? "Shows less of it" : "Shows more of it") : "")
        .onScrollVisibilityChange(threshold: 0.01) { if $0 { hasShown = true } }
        .task {
            guard preview == .html else { return }
            rules = await FilePreview.offlineRules()
            if rules == nil { failed() }
        }
    }

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        switch preview {
        case .markdown(let text):
            MarkdownView(markdown: text, fontSize: 13)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        case .html:
            if let rules, hasShown {
                PagePreview(url: file.url, workspace: file.workspace, rules: rules) { measured in
                    withAnimation(.smooth(duration: 0.25)) { contentHeight = measured ?? .infinity }
                } failed: {
                    failed()
                }
                .frame(height: height)
                .opacity(contentHeight == nil ? 0 : 1)
            } else {
                // Room for the page while it waits to load, which an empty strip wouldn't have.
                Color.clear
            }
        }
    }

    /// Opaque down to the last `fade` points, which fade out when the file `cuts` there.
    private func fadeOut(height: CGFloat, cuts: Bool) -> some View {
        let start = max(0, 1 - Self.fade / max(height, 1))
        return LinearGradient(
            stops: [.init(color: .black, location: 0), .init(color: .black, location: start), .init(color: .black.opacity(cuts ? 0 : 1), location: 1)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// How tall the strip is for a preview `content` tall: all of it up to `height`, or `enlargedHeight` once
    /// clicked, and `height` while a page is still loading.
    static func shownHeight(of content: CGFloat?, enlarged: Bool) -> CGFloat {
        guard let content else { return height }
        return max(0, min(content, enlarged ? enlargedHeight : height))
    }

    /// Whether a click shows more: the preview goes on past the strip.
    static func enlarges(_ content: CGFloat?) -> Bool {
        (content ?? 0) > height + 1
    }
}

extension FilePreview {
    /// How large a page is drawn: a little smaller than a browser would, so it lays out wider than the card.
    static let pageZoom: CGFloat = 0.8

    /// The rules that let a page load only files: anything it asks of the internet, a picture, a style, a font, a
    /// frame, is blocked before it goes out, so a page can't tell anyone it was looked at.
    static let offlineRuleList = """
        [{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
         {"trigger": {"url-filter": "^file:"}, "action": {"type": "ignore-previous-rules"}},
         {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
         {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}]
        """

    @MainActor private static var compiledRules: WKContentRuleList?

    /// `offlineRuleList`, compiled once. Nil when WebKit turns it down, and then no page is shown at all.
    @MainActor static func offlineRules() async -> WKContentRuleList? {
        if let compiledRules { return compiledRules }
        do {
            compiledRules = try await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "MeralineFilePreview", encodedContentRuleList: offlineRuleList)
        } catch {
            Log.panel.error("Couldn’t compile the rules for page previews: \(error.localizedDescription)")
        }
        return compiledRules
    }

    /// What previews keep while they are open: nothing on disk, and nothing shared with Safari or any other app.
    @MainActor static let dataStore = WKWebsiteDataStore.nonPersistent()
}

/// A page drawn by WebKit only to be looked at: scripts off, only its own file and the workspace's files loaded,
/// no navigating away, no sound or video playing by itself, and nothing kept.
struct PagePreview: NSViewRepresentable {
    let url: URL
    let workspace: URL
    let rules: WKContentRuleList
    /// The page's height in points once it has loaded, or nil when it couldn't be measured.
    var measured: (CGFloat?) -> Void
    var failed: () -> Void

    func makeCoordinator() -> Loader { Loader(url: url) }

    func makeNSView(context: Context) -> InertWebView {
        let loader = context.coordinator
        loader.measured = measured
        loader.failed = failed
        let view = Self.makeWebView(rules: rules, loader: loader)
        view.loadFileURL(url, allowingReadAccessTo: workspace)
        return view
    }

    func updateNSView(_ view: InertWebView, context: Context) {
        context.coordinator.measured = measured
        context.coordinator.failed = failed
    }

    static func dismantleNSView(_ view: InertWebView, coordinator: Loader) {
        view.stopLoading()
        view.navigationDelegate = nil
    }

    /// A web view set up as the preview's, with `loader` deciding what it may load.
    static func makeWebView(rules: WKContentRuleList, loader: Loader) -> InertWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = FilePreview.dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(rules)
        // Meraline's own script, which runs with the page's off: the page never scrolls, so it shows no scroll bar.
        configuration.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.style.setProperty('overflow', 'hidden', 'important')",
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient
        ))
        let view = InertWebView(frame: NSRect(x: 0, y: 0, width: 540, height: FilePreviewStrip.height), configuration: configuration)
        view.navigationDelegate = loader
        view.pageZoom = FilePreview.pageZoom
        view.allowsLinkPreview = false
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false
        view.wantsLayer = true
        view.layer?.cornerRadius = FilePreviewStrip.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    /// Loads the page and nothing after it, and measures it once it has loaded.
    final class Loader: NSObject, WKNavigationDelegate {
        let url: URL
        var measured: (CGFloat?) -> Void = { _ in }
        var failed: () -> Void = {}
        private var hasStarted = false
        private var hasFinished = false

        init(url: URL) {
            self.url = url
        }

        /// The page's own file, once, and frames of files inside it; no link, redirect, or refresh.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let frame = action.targetFrame, let target = action.request.url else { return .cancel }
            guard frame.isMainFrame else {
                return target.isFileURL || target.scheme == "about" ? .allow : .cancel
            }
            guard !hasStarted, target.isFileURL, target.standardizedFileURL.path == url.standardizedFileURL.path else { return .cancel }
            hasStarted = true
            return .allow
        }

        /// What WebKit can draw; never a download.
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            response.canShowMIMEType ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasFinished else { return }
            hasFinished = true
            let zoom = webView.pageZoom
            let script = "Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)"
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
                guard case .success(let value) = result, let height = (value as? NSNumber)?.doubleValue, height > 0 else {
                    self?.measured(nil)
                    return
                }
                self?.measured(ceil(height * zoom))
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Log.panel.error("A page preview’s web content ended")
            failed()
        }

        /// Only the page's own load failing ends the preview, not a link, redirect, or refresh turned down.
        private func fail(_ error: Error) {
            let error = error as NSError
            // WebKit's "Frame load interrupted", which a navigation its policy turned down ends with.
            let turnedDown = (error.domain == "WebKitErrorDomain" && error.code == 102)
                || (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            guard !hasFinished, !turnedDown else { return }
            hasFinished = true
            Log.panel.error("Couldn’t preview a page: \(error.localizedDescription)")
            failed()
        }
    }
}

/// A web view nothing reaches: clicks and scrolling go to what is behind it, it never takes the keyboard, and it
/// tracks no pointer, so a page shows no hover or pointing-hand cursor.
final class InertWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override func addTrackingArea(_ trackingArea: NSTrackingArea) {}
}
