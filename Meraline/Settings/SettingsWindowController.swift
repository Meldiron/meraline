import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let navigation = SettingsNavigation()

    init(preferences: Preferences, updater: Updater) {
        let hostingController = NSHostingController(
            rootView: SettingsView(preferences: preferences, updater: updater, navigation: navigation)
        )
        hostingController.sceneBridgingOptions = [.title, .toolbars]

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { navigation.selection = pane }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
