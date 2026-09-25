import AppKit
import KeyboardShortcuts
import Observation

@main
enum MeralineApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let updater = Updater()
    private lazy var session = ChatSession(preferences: preferences)
    private lazy var panel = PanelController(session: session, preferences: preferences) { [weak self] in
        self?.showSettings(nil)
    }
    private lazy var settings = SettingsWindowController(preferences: preferences, updater: updater)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggle() }
        observeMenuBarPreference()

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            panel.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func showPanel(_ sender: Any?) { panel.show() }

    @objc private func showSettings(_ sender: Any?) {
        panel.close()
        settings.show()
    }

    @objc private func checkForUpdates(_ sender: Any?) { updater.checkForUpdates() }

    @objc private func showAbout(_ sender: Any?) {
        panel.close()
        settings.show(.about)
    }

    private func observeMenuBarPreference() {
        withObservationTracking {
            updateStatusItem(visible: preferences.showsMenuBarIcon)
        } onChange: {
            Task { @MainActor [weak self] in self?.observeMenuBarPreference() }
        }
    }

    private func updateStatusItem(visible: Bool) {
        guard visible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Meraline")
        let menu = NSMenu()
        let ask = menu.addItem(withTitle: "Ask Meraline", action: #selector(showPanel), keyEquivalent: "")
        ask.target = self
        ask.setShortcut(for: .togglePanel)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if updater.isAvailable {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Meraline", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "Meraline")
        appMenu.addItem(withTitle: "About Meraline", action: #selector(showAbout), keyEquivalent: "").target = self
        if updater.isAvailable {
            appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Meraline", action: #selector(NSApplication.hide), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Meraline", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        mainMenu.addItem(submenu: appMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll), keyEquivalent: "a")
        mainMenu.addItem(submenu: editMenu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize), keyEquivalent: "m")
        mainMenu.addItem(submenu: windowMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
