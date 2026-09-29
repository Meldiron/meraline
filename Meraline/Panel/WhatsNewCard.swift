import SwiftUI

/// The notes of the update the What’s New capsule under the card announces, under the input: what Sparkle
/// carried when it installed the update, screenshots included, or only the way to GitHub after an install by
/// hand. Neutral glass, like the other rows.
struct WhatsNewCard: View {
    let update: Updater.Update
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var notesHeight: CGFloat = 0

    private var blocks: [ReleaseNotes.Block] {
        update.notes.map(ReleaseNotes.blocks(from:)) ?? []
    }

    /// Notes with screenshots scroll in a taller frame, so a whole screenshot fits.
    private var maximumNotesHeight: CGFloat {
        blocks.contains { if case .picture = $0 { true } else { false } } ? 400 : 240
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What’s new in Meraline \(update.version)")
                .font(.system(size: 13, weight: .semibold))
            if blocks.isEmpty {
                Text("Meraline was updated. Its release notes are on GitHub.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    notes
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { notesHeight = $0 }
                }
                .frame(height: min(notesHeight, maximumNotesHeight))
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
            HStack(spacing: 8) {
                Spacer()
                if let url = Bundle.main.releaseNotesURL(for: update.version) {
                    Button("Full Release Notes") { openURL(url) }
                        .buttonStyle(.glass)
                }
                Button("Got It", action: dismiss)
                    .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                    .hoverTip("Hide What’s New until the next update")
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(MarkdownText.render(text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let text):
                    Text(MarkdownText.render(text))
                        .fixedSize(horizontal: false, vertical: true)
                case .picture(let url, let caption):
                    NotePicture(url: url, caption: caption)
                        .padding(.vertical, 4)
                }
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// A screenshot from the notes, as wide as the card and at most `maximumHeight` tall, loaded when the notes
/// open. A click opens it full size in the browser. While it loads, a faint frame holds its place; one that
/// can't load leaves the notes without it.
private struct NotePicture: View {
    static let maximumHeight: CGFloat = 320
    /// Pictures loaded this launch, in memory only, so the notes open with them the next time.
    private static var loaded: [URL: NSImage] = [:]

    let url: URL
    let caption: String

    @Environment(\.openURL) private var openURL
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image ?? Self.loaded[url] {
                let aspect = image.size.width / max(image.size.height, 1)
                Button { openURL(url) } label: {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(aspect, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
                        .frame(maxWidth: Self.maximumHeight * aspect)
                }
                .buttonStyle(.plain)
                .hoverTip(caption.isEmpty ? "Open the picture" : caption)
            } else if !failed {
                // The shape of the README screenshots.
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(0.04))
                    .aspectRatio(1.6, contentMode: .fit)
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(maxWidth: Self.maximumHeight * 1.6)
            }
        }
        .accessibilityLabel(caption)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard Self.loaded[url] == nil else { return }
        do {
            let data = try await ReleaseNotePictures.data(at: url)
            guard let image = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            Self.loaded[url] = image
            self.image = image
        } catch {
            // The notes were folded away while it loaded.
            guard !Task.isCancelled else { return }
            Log.updates.error("A picture in the release notes didn’t load: \(error.localizedDescription)")
            failed = true
        }
    }
}

/// Fetches the screenshots in release notes. The session is ephemeral, so nothing it loads reaches the disk.
private nonisolated enum ReleaseNotePictures {
    private static let session = URLSession(configuration: .ephemeral)
    /// A screenshot is a few hundred kilobytes; anything far bigger isn't one.
    private static let sizeLimit = 10_000_000

    static func data(at url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= sizeLimit else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
