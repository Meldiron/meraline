#!/usr/bin/env swift
// Renders an HTML file to a PNG with exact pixel dimensions using WebKit.
//
// Usage: swift scripts/render_html_png.swift <input.html> <output.png> <width> <height> [scale]
//
// The page is laid out at <width> x <height> CSS pixels and rasterised at <scale> (1 for a
// plain image, 2 for a Retina rendition). The DMG background in assets/dmg is the only
// consumer today, but any HTML or SVG file works.

import AppKit
import WebKit

func usage() -> Never {
    FileHandle.standardError.write(
        "usage: render_html_png.swift <input.html> <output.png> <width> <height> [scale]\n".data(using: .utf8)!)
    exit(2)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 5,
      let pointWidth = Double(arguments[3]), pointWidth > 0,
      let pointHeight = Double(arguments[4]), pointHeight > 0
else { usage() }

let input = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let output = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let scale = arguments.count > 5 ? (Double(arguments[5]) ?? 1) : 1
let pixelWidth = Int((pointWidth * scale).rounded())
let pixelHeight = Int((pointHeight * scale).rounded())

guard FileManager.default.fileExists(atPath: input.path) else { fail("no such file: \(input.path)") }

final class Renderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private(set) var outcome: Result<Void, Error>?

    override init() {
        // The view is sized in pixels and the page zoomed to match, so a 2x render lays the
        // page out at the same CSS size as a 1x render and simply draws it twice as large.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        super.init()
        webView.navigationDelegate = self
        webView.pageZoom = scale
    }

    func start() {
        webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Fonts and gradients settle a moment after the navigation reports done.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.snapshot() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        outcome = .failure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        outcome = .failure(error)
    }

    private func snapshot() {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        webView.takeSnapshot(with: configuration) { image, error in
            self.outcome = Result {
                guard let image else { throw error ?? CocoaError(.fileWriteUnknown) }
                try Renderer.write(image)
            }
        }
    }

    // The snapshot's backing store follows the host display, so it is redrawn into a bitmap
    // of exactly the requested pixel size before encoding.
    private static func write(_ image: NSImage) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
                   from: .zero, operation: .copy, fraction: 1)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: output)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let renderer = Renderer()
renderer.start()

let deadline = Date().addingTimeInterval(60)
while renderer.outcome == nil && Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}

switch renderer.outcome {
case .success:
    print("Rendered \(output.lastPathComponent) at \(pixelWidth)x\(pixelHeight)")
case .failure(let error):
    fail(error.localizedDescription)
case nil:
    fail("timed out rendering \(input.path)")
}
