import AppKit
import UniformTypeIdentifiers

/// What the clipboard button above the window finds on the clipboard: files copied in Finder, a picture, or
/// text. When the clipboard holds both a picture and text, as copying from a document or a web page often
/// does, the kind the copying app put first wins, so a copied image stays a picture and a copied paragraph
/// stays words. A password copied from a password manager, which marks it concealed, is never read. What is
/// dropped on the window is judged the same way (`drop(of:)`).
/// Services › Ask Meraline reads what an app hands it the same way, but with text first (`readSelection`).
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
        read(from: pasteboard, pictureWins: picturesFirst)
    }

    /// What Services › Ask Meraline was handed with a selection: files, text, or a picture, as Preview and
    /// Photos hand over a selected image. Text wins over a picture whatever the app listed first, so a
    /// selection that is both, as a stretch of a web page can be, still comes as words, as it did before the
    /// service took pictures.
    static func readSelection(from pasteboard: NSPasteboard) -> ClipboardContent? {
        read(from: pasteboard) { _ in false }
    }

    /// Files, else text or a picture: a picture when there is no text or `pictureWins` says so of the kinds
    /// the first item lists.
    private static func read(from pasteboard: NSPasteboard, pictureWins: ([NSPasteboard.PasteboardType]) -> Bool) -> ClipboardContent? {
        guard !isConcealed(pasteboard.types ?? []) else { return nil }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { return .files(urls) }
        let text = pasteboard.string(forType: .string).flatMap { $0.trimmed.isEmpty ? nil : $0 }
        let types = pasteboard.pasteboardItems?.first?.types ?? pasteboard.types ?? []
        if text == nil || pictureWins(types), let image = NSImage(pasteboard: pasteboard) {
            return .image(image)
        }
        return text.map(ClipboardContent.text)
    }

    /// What one item dropped on the window brings.
    enum Drop: Equatable {
        case file
        case image
        /// Text dragged out of another app, for a card of its own, like a selection.
        case text
    }

    /// What an item dropped on the window brings, judged by its kinds, which the app it came from lists best
    /// first: a file, a picture, or text. A picture that brings text too comes as the picture when it is a web
    /// page's, which drags its address along as text, or when the app listed it first, as on the clipboard;
    /// otherwise as the text, since a word processor's drag carries a picture of the words. A password
    /// manager's drag, marked concealed, brings nothing.
    static func drop(of typeIdentifiers: [String]) -> Drop? {
        let types = typeIdentifiers.map { NSPasteboard.PasteboardType($0) }
        guard !isConcealed(types) else { return nil }
        let kinds = typeIdentifiers.compactMap { UTType($0) }
        if kinds.contains(where: { $0.conforms(to: .fileURL) }) { return .file }
        let hasText = kinds.contains { $0.conforms(to: .plainText) }
        if kinds.contains(where: { $0.conforms(to: .image) }),
           !hasText || kinds.contains(where: { $0.conforms(to: .url) }) || picturesFirst(types) {
            return .image
        }
        return hasText ? .text : nil
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
