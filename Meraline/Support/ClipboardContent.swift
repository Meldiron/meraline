import AppKit
import UniformTypeIdentifiers

/// What the clipboard button above the window finds on the clipboard: files copied in Finder, a picture, or
/// text. When the clipboard holds both a picture and text, as copying from a document or a web page often
/// does, the kind the copying app put first wins, so a copied image stays a picture and a copied paragraph
/// stays words. A password copied from a password manager, which marks it concealed, is never read.
enum ClipboardContent {
    case files([URL])
    case image(NSImage)
    case text(String)

    /// Marks password managers put on what they copy (see nspasteboard.org).
    static let concealedTypes = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    /// Whether `pasteboard` seems to hold something Meraline can add, judged by its kinds alone, without
    /// reading it: files, text, or a picture, and no password.
    static func hasContent(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types, !types.isEmpty, !isConcealed(types) else { return false }
        return types.contains(.fileURL) || types.contains(.string) || NSImage.canInit(with: pasteboard)
    }

    static func isConcealed(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { concealedTypes.contains($0) }
    }

    /// What `pasteboard` holds, or nil when there is nothing Meraline can add.
    static func read(from pasteboard: NSPasteboard) -> ClipboardContent? {
        guard !isConcealed(pasteboard.types ?? []) else { return nil }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { return .files(urls) }
        let text = pasteboard.string(forType: .string).flatMap { $0.trimmed.isEmpty ? nil : $0 }
        let types = pasteboard.pasteboardItems?.first?.types ?? pasteboard.types ?? []
        if text == nil || picturesFirst(types), let image = NSImage(pasteboard: pasteboard) {
            return .image(image)
        }
        return text.map(ClipboardContent.text)
    }

    /// Whether a picture comes before any text among the kinds an app copied, which it lists best first.
    static func picturesFirst(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        for type in types {
            guard let kind = UTType(type.rawValue) else { continue }
            if kind.conforms(to: .image) || kind.conforms(to: .pdf) { return true }
            if kind.conforms(to: .text) { return false }
        }
        return false
    }

    /// How it is described in the log: its kind and size, never what it says.
    var logDescription: String {
        switch self {
        case .files(let urls): "\(urls.count) file(s)"
        case .image: "an image"
        case .text(let text): "text, \(text.count) characters"
        }
    }
}
