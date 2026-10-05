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
    static let environment = ProcessInfo.processInfo.environment

    /// Where the pictures go. Unset, as in every other test run, the showcase is skipped.
    static let output: URL? = environment["MERALINE_SHOWCASE"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    /// The appearances to take each picture in, from MERALINE_SHOWCASE_APPEARANCE: dark, light, or both.
    static var appearances: [Appearance] {
        Appearance(rawValue: environment["MERALINE_SHOWCASE_APPEARANCE"] ?? "").map { [$0] } ?? [.dark, .light]
    }

    /// A picture to show across the whole screen behind a clip instead of the gradient, from MERALINE_CLIP_BACKDROP
    /// (`scripts/clips.sh --backdrop`): the promo's night sky, so a clip recorded here drops into its films.
    static let clipBackdrop: URL? = environment["MERALINE_CLIP_BACKDROP"].flatMap { $0.trimmed.isEmpty ? nil : URL(filePath: $0) }

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

/// A gradient window at the desktop's level, which the windows placed over it show their glass against; or, for
/// a clip meant for the promo's films, their night sky across the whole screen (`backdropImage`), with the panel
/// at the films' spot (`filmTopLeft(top:)`) and the films' region recorded (`ShowcaseStage.recordPanel`).
@MainActor
final class ShowcaseStage {
    static let desktop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

    let appearance: Showcase.Appearance
    let backdrop: NSWindow
    let screen: NSScreen
    /// Whether the backdrop is a film's sky across the screen rather than the gradient.
    let isFilmSet: Bool

    init(_ appearance: Showcase.Appearance, backdropImage: URL? = nil) {
        self.appearance = appearance
        screen = NSScreen.main ?? NSScreen.screens[0]
        let image = backdropImage.flatMap { NSImage(contentsOf: $0) }
        isFilmSet = image != nil
        let visible = screen.visibleFrame
        let frame = image == nil
            ? NSRect(x: visible.minX + 20, y: visible.minY + 20, width: min(1_000, visible.width - 40), height: min(1_000, visible.height - 40))
            : screen.frame
        backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.level = Self.desktop
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.isReleasedWhenClosed = false
        if let image {
            let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
            view.image = image
            view.imageScaling = .scaleAxesIndependently
            backdrop.contentView = view
        } else {
            let gradient = CAGradientLayer()
            gradient.frame = CGRect(origin: .zero, size: frame.size)
            gradient.startPoint = CGPoint(x: 0, y: 1)
            gradient.endPoint = CGPoint(x: 1, y: 0)
            gradient.colors = appearance.gradient
            let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            view.layer = gradient
            backdrop.contentView = view
        }
        backdrop.orderFrontRegardless()
        if let output = Showcase.output { try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    }

    /// Where a window's top left goes: a little inside the backdrop's.
    var topLeft: NSPoint { NSPoint(x: backdrop.frame.minX + 60, y: backdrop.frame.maxY - 40) }

    /// Where the promo's films have the panel: its left at 404 points, its top `top` points down the screen (250
    /// for a short chat, 110 for one that grows tall), in the films' own measure (see the promo's record scripts).
    func filmTopLeft(top: CGFloat) -> NSPoint { NSPoint(x: screen.frame.minX + 404, y: screen.frame.maxY - top) }

    /// The part of the screen the promo's films record, in points from the screen's top left: the 16:9 band the
    /// films show, 1512 by 850.5 points, 66 down.
    static let filmRegion = CGRect(x: 0, y: 66, width: 1_512, height: 850.5)

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

    /// A window with what it has open over it, a sheet and a popover, over the gradient: ScreenCaptureKit takes
    /// just those windows, in the frame around all of them with room for their shadows. The test host is active for
    /// the moment of the capture, as for `captureWindow(_:as:)`, so they draw active.
    func captureWindows(_ windows: [NSWindow], as name: String) async throws {
        guard Showcase.output != nil, let first = windows.first else { return }
        await Showcase.waitForIdle()
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        await Showcase.settle(0.8)
        let frame = windows.dropFirst().reduce(first.frame) { $0.union($1.frame) }.insetBy(dx: -36, dy: -36)
        let filter = SCContentFilter(display: try await display(), including: try await shareable([backdrop] + windows))
        let configuration = configuration(size: frame.size)
        configuration.sourceRect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        if let previous, previous != .current {
            NSApp.yieldActivation(to: previous)
            previous.activate(from: .current, options: [])
        }
        try write(image, as: name)
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

    /// The stage's windows as ScreenCaptureKit lists them, hidden ones included, for a capture of just those.
    func shareable(_ windows: [NSWindow]) async throws -> [SCWindow] {
        let numbers = Set(windows.map { CGWindowID($0.windowNumber) })
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let found = content.windows.filter { numbers.contains($0.windowID) }
        guard found.count == windows.count else { throw ShowcaseError.windowNotFound }
        return found
    }

    func display() async throws -> SCDisplay {
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
