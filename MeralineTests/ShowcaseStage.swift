import AppKit
import ScreenCaptureKit
import SwiftUI
@testable import Meraline

/// Pictures of Meraline for the README and the release notes, taken without taking over the Mac.
/// `scripts/showcase.sh` runs `ShowcaseTests`, which build the real panel and Settings window in the test host with
/// scripted state, put them at the desktop's level behind every other window, over the screenshots' gradient, and
/// capture only those windows with ScreenCaptureKit, so the glass is drawn as it is on screen. Nothing is clicked or
/// typed. A window draws its active look (the pink glass tints, the text cursor, the traffic lights) only while it
/// has the keyboard, so each capture waits until no one has touched the Mac for a few seconds, then takes the
/// keyboard for about a second: the panel without activating the test host, as Meraline's own window does, and
/// Settings by activating it, handing activation back to the app that had it.
nonisolated enum Showcase {
    private static let environment = ProcessInfo.processInfo.environment

    /// Where the pictures go. Unset, as in every other test run, the showcase is skipped.
    static let output: URL? = environment["MERALINE_SHOWCASE"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    /// The appearances to take each picture in, from MERALINE_SHOWCASE_APPEARANCE: dark, light, or both.
    static var appearances: [Appearance] {
        Appearance(rawValue: environment["MERALINE_SHOWCASE_APPEARANCE"] ?? "").map { [$0] } ?? [.dark, .light]
    }

    /// Whether to take the picture `name`: MERALINE_SHOWCASE_ONLY names the ones to take, or all when unset.
    static func wants(_ name: String) -> Bool {
        guard let only = environment["MERALINE_SHOWCASE_ONLY"], !only.trimmed.isEmpty else { return true }
        return only.split(separator: " ").contains { $0 == name }
    }

    enum Appearance: String {
        case dark, light

        /// The file name's ending: panel.png is dark, panel-light.png light, as the README's pictures are.
        var suffix: String { self == .light ? "-light" : "" }
        var appearance: NSAppearance? { NSAppearance(named: self == .light ? .aqua : .darkAqua) }

        /// The backdrop of `scripts/lib/screenshots/backdrop.swift`, so both scripts' pictures match.
        var gradient: [CGColor] {
            switch self {
            case .light:
                [NSColor(red: 0.96, green: 0.93, blue: 0.97, alpha: 1).cgColor, NSColor(red: 0.88, green: 0.90, blue: 0.98, alpha: 1).cgColor,
                 NSColor(red: 0.98, green: 0.91, blue: 0.94, alpha: 1).cgColor]
            case .dark:
                [NSColor(red: 0.13, green: 0.10, blue: 0.22, alpha: 1).cgColor, NSColor(red: 0.09, green: 0.10, blue: 0.20, alpha: 1).cgColor,
                 NSColor(red: 0.20, green: 0.10, blue: 0.19, alpha: 1).cgColor]
            }
        }
    }

    /// Waits until the keyboard, mouse, and trackpad have been still for `seconds`, so taking the keyboard for a
    /// moment catches no one's typing.
    static func waitForIdle(_ seconds: Double = 5) async {
        let anyInput = CGEventType(rawValue: ~0)!
        while CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput) < seconds {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Runs the display cycle for a while, for SwiftUI to lay out and animate.
    static func settle(_ seconds: Double = 1) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// A gradient window at the desktop's level, which the windows placed over it show their glass against.
@MainActor
final class ShowcaseStage {
    static let desktop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

    let appearance: Showcase.Appearance
    private let backdrop: NSWindow
    private let screen: NSScreen

    init(_ appearance: Showcase.Appearance) {
        self.appearance = appearance
        screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.minX + 20, y: visible.minY + 20, width: min(1_000, visible.width - 40), height: min(1_000, visible.height - 40))
        backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.level = Self.desktop
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.isReleasedWhenClosed = false
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(origin: .zero, size: frame.size)
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.colors = appearance.gradient
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer = gradient
        backdrop.contentView = view
        backdrop.orderFrontRegardless()
        if let output = Showcase.output { try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    }

    /// Where a window's top left goes: a little inside the backdrop's.
    var topLeft: NSPoint { NSPoint(x: backdrop.frame.minX + 60, y: backdrop.frame.maxY - 40) }

    /// Puts `window` over the backdrop, behind every other window, in the stage's appearance.
    func place(_ window: NSWindow) {
        window.appearance = appearance.appearance
        window.level = Self.desktop
        window.ignoresMouseEvents = true
        window.setFrameTopLeftPoint(topLeft)
        window.order(.above, relativeTo: backdrop.windowNumber)
    }

    /// The panel as the screenshots show it: its whole window, the margins around the card included, over the
    /// gradient. It has the keyboard for the moment of the capture, without activating the test host.
    func capturePanel(_ panel: NSWindow, as name: String) async throws {
        panel.setFrameTopLeftPoint(topLeft)
        await Showcase.waitForIdle()
        panel.makeKey()
        await Showcase.settle(0.6)
        let windows = try await shareable([panel, backdrop])
        let filter = SCContentFilter(display: try await display(), including: windows)
        let frame = panel.frame
        let configuration = configuration(size: frame.size)
        // ScreenCaptureKit counts from the display's top left.
        configuration.sourceRect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        panel.resignKey()
        try write(image, as: name)
    }

    /// A titled window alone, with its shadow, as the README's Settings pictures are: `screencapture -l` takes the
    /// window by its number, whatever covers it. It draws active only while the test host is, so the test host is
    /// active for the moment of the capture, and the app that was hands back.
    func captureWindow(_ window: NSWindow, as name: String) async throws {
        guard let output = Showcase.output else { return }
        await Showcase.waitForIdle()
        let previous = NSWorkspace.shared.frontmostApplication
        // A plain activate() is only a request, which macOS turns down while another app is in front.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        await Showcase.settle(0.8)
        let file = output.appending(path: "\(name)\(appearance.suffix).png")
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), file.path]
        try capture.run()
        capture.waitUntilExit()
        if let previous, previous != .current {
            NSApp.yieldActivation(to: previous)
            previous.activate(from: .current, options: [])
        }
        guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: file.path) else { throw ShowcaseError.notWritten }
        FileHandle.standardError.write(Data("Showcase: \(file.lastPathComponent)\n".utf8))
    }

    func close(_ windows: NSWindow?...) {
        for window in windows { window?.orderOut(nil) }
        backdrop.orderOut(nil)
    }

    private func configuration(size: CGSize) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width * screen.backingScaleFactor)
        configuration.height = Int(size.height * screen.backingScaleFactor)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return configuration
    }

    private func shareable(_ windows: [NSWindow]) async throws -> [SCWindow] {
        let numbers = Set(windows.map { CGWindowID($0.windowNumber) })
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let found = content.windows.filter { numbers.contains($0.windowID) }
        guard found.count == windows.count else { throw ShowcaseError.windowNotFound }
        return found
    }

    private func display() async throws -> SCDisplay {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == number }) else { throw ShowcaseError.windowNotFound }
        return display
    }

    private func write(_ image: CGImage, as name: String) throws {
        guard let output = Showcase.output else { return }
        let file = output.appending(path: "\(name)\(appearance.suffix).png")
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw ShowcaseError.notWritten }
        try data.write(to: file)
        FileHandle.standardError.write(Data("Showcase: \(file.lastPathComponent)\n".utf8))
    }

    enum ShowcaseError: Error {
        case windowNotFound, notWritten
    }
}

extension NSView {
    /// The views of `type` inside this one, depth first.
    func showcaseDescendants<View: NSView>(of type: View.Type) -> [View] {
        subviews.flatMap { subview in ((subview as? View).map { [$0] } ?? []) + subview.showcaseDescendants(of: type) }
    }
}
