import AppKit
import UniformTypeIdentifiers

nonisolated struct ImageAttachment: Identifiable, Equatable, Sendable {
    static let limit = 5
    private static let maximumPixelSize = 2_048
    private static let maximumByteCount = 8 * 1_024 * 1_024

    let id = UUID()
    let mediaType: String
    let data: Data

    var base64: String { data.base64EncodedString() }
    var dataURL: String { "data:\(mediaType);base64,\(base64)" }

    /// Whether the file at `url` is an image, by its type, without reading it.
    static func isImage(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true
    }

    static func load(from url: URL) throws -> ImageAttachment {
        guard let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType,
              type.conforms(to: .image),
              let image = NSImage(contentsOf: url) else {
            throw AttachmentError.unreadable
        }
        return try make(from: image)
    }

    static func make(from image: NSImage) throws -> ImageAttachment {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AttachmentError.unreadable
        }
        let scale = min(1, CGFloat(maximumPixelSize) / CGFloat(max(source.width, source.height)))
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AttachmentError.unreadable
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage() else { throw AttachmentError.unreadable }

        let bitmap = NSBitmapImageRep(cgImage: rendered)
        if let png = bitmap.representation(using: .png, properties: [:]), png.count <= maximumByteCount {
            return ImageAttachment(mediaType: "image/png", data: png)
        }
        if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]),
           jpeg.count <= maximumByteCount {
            return ImageAttachment(mediaType: "image/jpeg", data: jpeg)
        }
        throw AttachmentError.tooLarge
    }
}

nonisolated enum AttachmentError: LocalizedError, Equatable {
    case unreadable
    case tooLarge
    case limitReached
    case unreadableFile
    case tooManyFiles(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "Meraline can’t read that image."
        case .tooLarge: "That image is too large to attach."
        case .limitReached: "You can attach up to \(ImageAttachment.limit) images."
        case .unreadableFile: "Meraline can’t open that file."
        case .tooManyFiles(let name): "“\(name)” has too many files to copy. Meraline copies up to \(FileAttachment.folderLimit.formatted()) from a folder, leaving out what git ignores."
        }
    }
}
