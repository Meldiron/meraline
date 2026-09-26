import AppKit
import Observation
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let navigation = SettingsNavigation()

    init(preferences: Preferences, updater: Updater) {
        let hostingController = NSHostingController(
            rootView: SettingsView(preferences: preferences, updater: updater, navigation: navigation)
        )
        hostingController.sceneBridgingOptions = [.toolbars]

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.setContentSize(NSSize(width: 715, height: 560))
        window.contentMinSize = NSSize(width: 715, height: 440)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setFrameAutosaveName("MeralineSettings")
        window.center()
        super.init(window: window)
        observeTitle()
    }

    /// The window is named after the selected pane, like System Settings. SwiftUI's title bridging
    /// doesn't reach a NavigationSplitView detail inside a hosting controller, so it's done here.
    private func observeTitle() {
        withObservationTracking {
            window?.title = navigation.selection?.title ?? "Settings"
        } onChange: {
            Task { @MainActor [weak self] in self?.observeTitle() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { navigation.selection = pane }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Nothing on the pane is focused when the window opens. AppKit would otherwise focus its first
        // text field, and a model field would pop open its suggestions.
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
    }
}
