import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Meraline

@MainActor
struct PresentedPictureTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "PresentedPictureTests-\(UUID().uuidString)")

    private func png(_ name: String, width: Int, height: Int) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = folder.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func file(at url: URL, isFolder: Bool = false) -> PresentedFile {
        PresentedFile(url: url, path: url.lastPathComponent, isFolder: isFolder)
    }

    @Test func aLargePictureComesSmallerWithItsShape() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = try #require(PresentedFile.picture(at: try png("big.png", width: 2_400, height: 1_600)))
        #expect(picture.width == 1_200)
        #expect(picture.height == 800)
    }

    @Test func aSmallPictureKeepsItsOwnSize() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = try #require(PresentedFile.picture(at: try png("icon.png", width: 64, height: 48)))
        #expect(picture.width == 64)
        #expect(picture.height == 48)
    }

    @Test func onlyPicturesAreShown() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try png("tree.png", width: 48, height: 64)
        let text = folder.appending(path: "notes.txt")
        try "Not a picture".write(to: text, atomically: true, encoding: .utf8)
        #expect(file(at: image).isImage)
        #expect(!file(at: text).isImage)
        #expect(!file(at: folder, isFolder: true).isImage)
        #expect(PresentedFile.picture(at: text) == nil)
    }

    @Test func aPictureFitsItsLimitItsPixelsAndTheCard() {
        let portrait = CGSize(width: 480, height: 640)
        #expect(PresentedFileCard.height(of: portrait, fitting: 560, limit: 200) == 200)
        #expect(PresentedFileCard.height(of: portrait, fitting: 560, limit: 420) == 420)
        let panorama = CGSize(width: 4_000, height: 1_000)
        #expect(PresentedFileCard.height(of: panorama, fitting: 560, limit: 200) == 140)
        #expect(PresentedFileCard.height(of: panorama, fitting: 560, limit: 480) == 140, "as wide as the card already")
        let icon = CGSize(width: 64, height: 48)
        #expect(PresentedFileCard.height(of: icon, fitting: 560, limit: 480) == 48, "never larger than its pixels")
        #expect(PresentedFileCard.height(of: .zero, fitting: 560, limit: 200) == 0)
    }
}
