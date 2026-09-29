import SwiftUI

/// A file an agent handed over, under its answer: its Finder icon, its name, and what it is, with Open in the app the
/// Mac opens it with, Show in Finder, Copy, and Save to Downloads. Dragging the card takes the file anywhere a file
/// from Finder goes. Once the file has left the workspace, the card says so and offers nothing. Neutral glass, with
/// the panel's faint pink on Open. A picture shows itself above its name instead of its icon, and a click on it
/// shows it larger, inside the window: the window closes when another one, such as Quick Look's, takes the keyboard.
/// A page or a Markdown file shows a preview there instead (`FilePreviewStrip`), which a click shows more of.
struct PresentedFileCard: View {
    /// How tall a picture shows, and how tall once clicked. Never taller than its own pixels.
    static let pictureHeight: CGFloat = 200
    static let enlargedPictureHeight: CGFloat = 420

    let file: PresentedFile
    var actions = PresentedFiles.shared

    /// The app Open uses, looked up once rather than on every word of an answer still coming in.
    @State private var opener: URL?
    /// The file's picture, when it is one ImageIO can read.
    @State private var picture: NSImage?
    /// The file's preview, when it is a page or Markdown, and whether the page turned out not to show.
    @State private var preview: FilePreview?
    @State private var previewFailed = false
    @State private var isEnlarged = false
    /// The card's width inside its padding, which a wide picture fills.
    @State private var width: CGFloat = 0

    private var notice: PresentedFiles.Notice? { actions.notice(for: file) }

    var body: some View {
        let exists = file.exists
        let shown = exists ? picture : nil
        let previewed = exists && shown == nil && !previewFailed ? preview : nil
        VStack(alignment: .leading, spacing: 10) {
            if let shown {
                pictureButton(shown)
            } else if let previewed {
                FilePreviewStrip(file: file, preview: previewed) { previewFailed = true }
            }
            row(exists: exists, showsIcon: shown == nil && previewed == nil)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .onDrag {
            guard file.exists else { return NSItemProvider() }
            file.markAsDownloaded()
            Log.chat.info("Dragging a handed-over file out")
            return NSItemProvider(object: file.url as NSURL)
        }
        .animation(.smooth(duration: 0.2), value: notice)
        .task(id: file.id) {
            opener = file.opener
            let url = file.url
            if file.isImage {
                let image = await Task.detached(priority: .userInitiated) { PresentedFile.picture(at: url) }.value
                picture = image.map { NSImage(cgImage: $0, size: .zero) }
            } else if !file.isFolder {
                preview = await Task.detached(priority: .userInitiated) { FilePreview.preview(at: url) }.value
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(file.name), handed over by the agent")
    }

    private func row(exists: Bool, showsIcon: Bool) -> some View {
        HStack(spacing: 10) {
            if showsIcon {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .opacity(exists ? 1 : 0.4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status(exists: exists))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
            }
            .hoverTip(file.path)
            Spacer(minLength: 8)
            if exists {
                if let opener {
                    Button("Open in \(PresentedFile.appName(opener))") { actions.open(file) }
                        .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                        .lineLimit(1)
                        .hoverTip(file.isFolder ? "Open the folder in Finder" : "Open \(file.name) in \(PresentedFile.appName(opener))")
                }
                iconButton("folder", label: "Show in Finder") { actions.showInFinder([file]) }
                iconButton(notice == .copied ? "checkmark" : "doc.on.doc", label: "Copy") { actions.copy([file]) }
                iconButton(isSaved ? "checkmark" : "square.and.arrow.down", label: "Save to Downloads") {
                    actions.saveToDownloads([file])
                }
                .disabled(notice == .saving)
            }
        }
    }

    /// The picture, as large as fits under `pictureHeight`, or `enlargedPictureHeight` once clicked. A picture that
    /// already shows whole, being small or as wide as the card, has nothing larger to show.
    private func pictureButton(_ image: NSImage) -> some View {
        let pixels = image.size
        let small = Self.height(of: pixels, fitting: width, limit: Self.pictureHeight)
        let large = Self.height(of: pixels, fitting: width, limit: Self.enlargedPictureHeight)
        let enlarges = large > small + 1
        let height = isEnlarged && enlarges ? large : small
        return Button {
            guard enlarges else { return }
            withAnimation(.smooth(duration: 0.25)) { isEnlarged.toggle() }
        } label: {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: height * pixels.width / max(pixels.height, 1), height: height)
                .clipShape(.rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        }
        .buttonStyle(.plain)
        .hoverTip(enlarges ? (isEnlarged ? "Show it smaller" : "Show it larger") : file.name)
        .accessibilityLabel("Picture of \(file.name)")
        .accessibilityHint(enlarges ? (isEnlarged ? "Shows it smaller" : "Shows it larger") : "")
    }

    /// How tall a picture of `pixels` shows in `width`: at most `limit`, its own height, and the height at which
    /// it fills the width.
    static func height(of pixels: CGSize, fitting width: CGFloat, limit: CGFloat) -> CGFloat {
        guard pixels.width > 0, pixels.height > 0 else { return 0 }
        return max(0, min(limit, pixels.height, width * pixels.height / pixels.width))
    }

    private var isSaved: Bool {
        if case .saved = notice { true } else { false }
    }

    private func status(exists: Bool) -> String {
        switch notice {
        case .copied?: return "Copied"
        case .saving?: return "Saving to Downloads…"
        case .saved(let name)?: return name == file.name ? "Saved to Downloads" : "Saved to Downloads as “\(name)”"
        case .failed(let message)?: return "Couldn’t save: \(message)"
        case .gone?: return "No longer in the agent’s folder"
        case nil: return exists ? file.summary : "No longer in the agent’s folder"
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverTip(label)
        .accessibilityLabel(label)
    }
}
