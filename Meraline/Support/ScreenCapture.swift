import AppKit
import ScreenCaptureKit

/// A screenshot for the next question: the screen the window is on, with Meraline's own windows left out of
/// the picture, so it shows what is behind the window. Nothing is recorded: one picture is taken when you ask
/// for it, and it lives in memory like any image in the chat. It needs Screen Recording access, which you give
/// in System Settings › Privacy & Security › Screen & System Audio Recording.
enum ScreenCapture {
    enum Failure: Error {
        /// Screen Recording access is off.
        case noAccess
        /// ScreenCaptureKit doesn't offer the screen, such as one just unplugged.
        case noDisplay
    }

    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// The screen as it looks without Meraline, at its full resolution. Attaching the picture makes it small
    /// enough for a model (see `ImageAttachment`).
    static func image(of screen: NSScreen) async throws -> NSImage {
        guard hasAccess else { throw Failure.noAccess }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw Failure.noAccess
        }
        guard let number = screen.displayNumber,
              let display = content.displays.first(where: { $0.displayID == number }) else { throw Failure.noDisplay }
        let meraline = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: meraline, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: image, size: filter.contentRect.size)
    }

    /// Starts over, as Accessibility does (see `SelectionAccess.request()`): takes Meraline out of the Screen
    /// Recording list, then shows the system's own request, which puts this copy back in it, ready to switch
    /// on. macOS keeps the switch for the code signature that asked first, so another build of Meraline can
    /// leave one that looks on and still refuses this copy. Only Meraline's own entry is reset, and only
    /// while it doesn't work.
    static func requestAccess() {
        guard !hasAccess else { return }
        Log.app.info("Asking for Screen Recording access")
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.meldiron.meraline"
        Task {
            await Task.detached {
                let reset = Process()
                reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                reset.arguments = ["reset", "ScreenCapture", bundleIdentifier]
                reset.standardOutput = FileHandle.nullDevice
                reset.standardError = FileHandle.nullDevice
                do {
                    try reset.run()
                    reset.waitUntilExit()
                } catch {
                    Log.app.error("Couldn’t reset Screen Recording access: \(error.localizedDescription)")
                }
            }.value
            _ = CGRequestScreenCaptureAccess()
        }
    }
}

private extension NSScreen {
    /// The display's number, as ScreenCaptureKit knows it.
    var displayNumber: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
