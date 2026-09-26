import AppKit
import Observation

/// Where the things the buttons above the card added came from, so each button knows whether what it would
/// add now is in the draft already, in which case it takes it out instead. The clipboard is known by the
/// pasteboard's change count, which moves with every copy. The screen is known by a visit, which starts each
/// time the window opens, the app in front changes, or the window moves to another screen, so a screenshot
/// of each app you visit comes along, and a second click on the same visit takes its screenshot out again.
/// In memory only, like the draft.
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
