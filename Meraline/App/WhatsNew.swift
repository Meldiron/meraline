import AppKit
import SwiftUI

/// Release notes as they arrive in an appcast item: Markdown with headings, bullets, and inline
/// styling. The What's new window renders these blocks with the panel's inline Markdown renderer.
nonisolated enum ReleaseNotes {
    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmed
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("#") {
                flush()
                blocks.append(.heading(String(line.drop { $0 == "#" }).trimmed))
            } else if let marker = ["- ", "* ", "• "].first(where: line.hasPrefix) {
                flush()
                blocks.append(.bullet(String(line.dropFirst(marker.count)).trimmed))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// Enough for an appcast that carries HTML notes: tags go, the common entities come back.
    static func strippingHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmed
    }
}

struct WhatsNewView: View {
    let update: Updater.Update
    let releaseNotesURL: URL?
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("What’s new in Meraline \(update.version)")
                .font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let notes = update.notes {
                        ForEach(Array(ReleaseNotes.blocks(from: notes).enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .heading(let text):
                                Text(text).font(.headline).padding(.top, 4)
                            case .bullet(let text):
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(MarkdownText.render(text))
                                }
                            case .paragraph(let text):
                                Text(MarkdownText.render(text))
                            }
                        }
                    } else {
                        Text("Meraline was updated. The release notes are on GitHub.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
            HStack {
                if let releaseNotesURL {
                    Link("Full Release Notes", destination: releaseNotesURL)
                }
                Spacer()
                Button("OK", action: dismiss)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.meralinePink)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// Shown once after an update installs, with the notes Sparkle carried for it.
final class WhatsNewWindowController: NSWindowController {
    private final class Dismisser {
        var action: () -> Void = {}
    }

    private let dismisser = Dismisser()

    init(update: Updater.Update) {
        let dismisser = self.dismisser
        let view = WhatsNewView(
            update: update,
            releaseNotesURL: Bundle.main.releaseNotesURL(for: update.version),
            dismiss: { dismisser.action() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        super.init(window: window)
        dismisser.action = { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
