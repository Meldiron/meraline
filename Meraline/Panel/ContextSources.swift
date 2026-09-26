import AppKit
import Observation

/// Where the things the buttons above the card added came from, so each button knows whether what it would
/// add now is in the draft already, in which case it takes it out instead. The clipboard is known by the
/// pasteboard's change count, which moves with every copy. The screen is known by a visit, which starts each
/// time the window opens, the app in front changes, or the window moves to another screen, so a screenshot
/// of each app you visit comes along, and a second click on the same visit takes its screenshot out again.
/// Adding from the clipboard or the screen happens here, for the buttons and for `meraline://ask` alike, and
/// so does what the buttons have to say about it. In memory only, like the draft.
@Observable
final class ContextSources {
    enum Origin: Hashable {
        case clipboard(change: Int)
        case screen(visit: Int)
    }

    /// The pasteboard's change count when it was last looked at.
    private(set) var clipboardChange = -1
    /// Whether the clipboard held something to add when it was last looked at, judged by its kinds alone.
    private(set) var clipboardHasContent = false
    private(set) var screenVisit = 0
    /// What the buttons have to say, in a capsule beside them.
    var notice: ContextButtons.Note?
    /// Counts the notices shown, so one shown again stays its full time.
    private(set) var noticesShown = 0
    /// Count what the clipboard and the screen added, for their buttons to bounce.
    private(set) var clipboardsAdded = 0
    private(set) var screenshotsAdded = 0
    private(set) var isCapturing = false
    private var origins: [UUID: Origin] = [:]
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var watch: Task<Void, Never>?

    /// How often the clipboard is looked at while the window is up: its change count only, unless it moved.
    static let clipboardInterval: Duration = .seconds(0.75)

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        refreshClipboard()
    }

    var clipboard: Origin { .clipboard(change: clipboardChange) }
    var screen: Origin { .screen(visit: screenVisit) }

    /// The draft's texts, images, and files that came from `origin`.
    func items(from origin: Origin, in session: ChatSession) -> Set<UUID> {
        session.draftContextIDs.filter { origins[$0] == origin }
    }

    /// Remembers where the draft's `ids` came from, and forgets items that have left the draft.
    func note(_ ids: Set<UUID>, from origin: Origin, in session: ChatSession) {
        let live = session.draftContextIDs
        origins = origins.filter { live.contains($0.key) }
        for id in ids where live.contains(id) { origins[id] = origin }
    }

    /// Adds what is on the clipboard, unless that very copy is in the draft already. Whether the copy is in
    /// the draft now: false, with a notice, when there was nothing to add.
    @discardableResult
    func addClipboard(to session: ChatSession) -> Bool {
        refreshClipboard()
        let origin = clipboard
        guard items(from: origin, in: session).isEmpty else { return true }
        guard let content = ClipboardContent.read(from: pasteboard) else {
            Log.panel.info("Clipboard: nothing to add")
            show(.emptyClipboard)
            return false
        }
        Log.panel.info("Clipboard added \(content.logDescription)")
        let added = session.addClipboard(content)
        note(added, from: origin, in: session)
        clipboardsAdded += 1
        return !added.isEmpty
    }

    /// Adds a screenshot of `screen`, without Meraline's windows, unless this visit's screenshot is in the
    /// draft already. Whether it is in the draft now: false, with a notice, when it couldn't be taken.
    @discardableResult
    func addScreenshot(of screen: NSScreen?, to session: ChatSession) async -> Bool {
        let origin = self.screen
        guard items(from: origin, in: session).isEmpty else { return true }
        guard !isCapturing else { return false }
        guard ScreenCapture.hasAccess else {
            Log.panel.info("Screenshot: no Screen Recording access")
            show(.noScreenAccess)
            return false
        }
        guard let screen else {
            show(.screenshotFailed)
            return false
        }
        isCapturing = true
        defer { isCapturing = false }
        do {
            let image = try await ScreenCapture.image(of: screen)
            let before = session.draftContextIDs
            session.attach(image)
            let added = session.draftContextIDs.subtracting(before)
            note(added, from: origin, in: session)
            Log.panel.info("Screenshot added the screen")
            if notice == .noScreenAccess { notice = nil }
            screenshotsAdded += 1
            return !added.isEmpty
        } catch ScreenCapture.Failure.noAccess {
            Log.panel.info("Screenshot: Screen Recording access refused")
            show(.noScreenAccess)
        } catch {
            Log.panel.error("Screenshot failed: \(error.localizedDescription)")
            show(.screenshotFailed)
        }
        return false
    }

    func show(_ notice: ContextButtons.Note) {
        self.notice = notice
        noticesShown += 1
    }

    /// Looks at the clipboard's change count, and at its kinds when that moved.
    func refreshClipboard() {
        let change = pasteboard.changeCount
        guard change != clipboardChange else { return }
        clipboardChange = change
        let hasContent = ClipboardContent.hasContent(pasteboard)
        if hasContent != clipboardHasContent { clipboardHasContent = hasContent }
    }

    /// The window opened: a new visit to the screen, and the clipboard watched while the window is up.
    func windowOpened() {
        screenVisit += 1
        refreshClipboard()
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.clipboardInterval)
                self?.refreshClipboard()
            }
        }
    }

    func windowClosed() {
        watch?.cancel()
        watch = nil
    }

    /// The app in front changed, or the window moved to another screen, while the window was up.
    func screenChanged() {
        screenVisit += 1
    }
}
