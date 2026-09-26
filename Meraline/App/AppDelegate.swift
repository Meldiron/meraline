import AppKit
import KeyboardShortcuts
import Observation

@main
enum MeralineApp {
    static func main() {
        // An agent that has already exited must not take Meraline down when an answer is written to it.
        signal(SIGPIPE, SIG_IGN)
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let updater = Updater(preferences: .shared)
    private lazy var session = ChatSession(preferences: preferences)
    private let whatsNew = WhatsNew()
    private lazy var panel: PanelController = PanelController(session: session, preferences: preferences, whatsNew: whatsNew) { [weak self] pane in
        self?.panel.close()
        self?.settings.show(pane)
    }
    private lazy var settings = SettingsWindowController(preferences: preferences, updater: updater)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Meraline \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber)) launched")
        ChatWorkspace.removeStale()
        NSApp.mainMenu = makeMainMenu()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggle() }
        observeMenuBarPreference()
        MCPServerRegistry.shared.refreshAll(preferences)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            defaults.set(true, forKey: "hasLaunchedBefore")
            defaults.set(Bundle.main.shortVersion, forKey: "lastRunVersion")
            panel.show()
        } else {
            announceUpdate()
        }
    }

    /// The `meraline://` scheme. See AutomationRoute for the routes.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let route = AutomationRoute(url: url) else {
                Log.app.error("Ignored unknown URL route: \(url.host() ?? url.absoluteString)")
                continue
            }
            switch route {
            case .ask(let text, let send):
                Log.app.info("URL route: ask\(text == nil ? "" : " with text")\(send ? ", send" : "")")
                panel.show()
                if let text { session.draft = text }
                if send { session.send() }
            case .newChat:
                Log.app.info("URL route: new chat")
                session.reset()
                panel.show()
            case .settings(let name):
                let pane = name.flatMap(SettingsPane.init(named:))
                Log.app.info("URL route: settings\(pane.map { " on \($0.title)" } ?? "")")
                panel.close()
                settings.show(pane)
            }
        }
    }

    /// After an update, the panel offers the notes Sparkle carried for the running version, or a
    /// link to the release when it was installed by hand, until they are dismissed. Nothing is
    /// announced on a fresh install.
    private func announceUpdate() {
        let defaults = UserDefaults.standard
        let current = Bundle.main.shortVersion
        // Copies from before this feature never stored a version; having launched before is
        // enough to know this is an update rather than a first run.
        let previous = defaults.string(forKey: "lastRunVersion") ?? "an earlier version"
        defaults.set(current, forKey: "lastRunVersion")
        guard previous != current else { return }
        Log.app.info("Updated from \(previous) to \(current)")
        whatsNew.announce(updater.takeWhatsNew(for: current) ?? Updater.Update(version: current, notes: nil))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        ChatWorkspace.removeAll()
    }

    @objc private func showPanel(_ sender: Any?) { panel.show() }

    @objc private func showSettings(_ sender: Any?) {
        panel.close()
        settings.show()
    }

    @objc private func checkForUpdates(_ sender: Any?) { updater.checkForUpdates() }

    @objc private func installStagedUpdate(_ sender: Any?) { updater.installStagedUpdate() }

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
        menu.delegate = self
        populateStatusMenu(menu)
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt each time the menu opens, so an update Sparkle found or staged shows up in it.
    private func populateStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let ask = menu.addItem(withTitle: "Ask Meraline", action: #selector(showPanel), keyEquivalent: "")
        ask.target = self
        ask.setShortcut(for: .togglePanel)
        menu.addItem(.separator())
        if let staged = updater.stagedUpdate {
            let install = menu.addItem(withTitle: "Restart to Update to \(staged.version)", action: #selector(installStagedUpdate), keyEquivalent: "")
            install.target = self
            install.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(.separator())
        } else if let available = updater.availableUpdate {
            let update = menu.addItem(withTitle: "Update to Meraline \(available.version)…", action: #selector(checkForUpdates), keyEquivalent: "")
            update.target = self
            update.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if updater.isAvailable, updater.state == .idle {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Meraline", action: #selector(NSApplication.terminate), keyEquivalent: "q")
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

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        populateStatusMenu(menu)
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
