import AppKit
import KeyboardShortcuts
import Observation

@main
enum MeralineApp {
    static func main() {
        // An agent that has already exited must not take Meraline down when an answer is written to it.
        signal(SIGPIPE, SIG_IGN)
        // An agent runs Meraline's own MCP server as this executable; that process serves it and nothing else.
        if let workspace = PresentFilesServer.workspace(in: CommandLine.arguments) {
            PresentFilesServer.serve(in: workspace)
            return
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        // Hosting the tests, Meraline runs without starting: no Keychain, shortcut, menu bar item, or updater.
        // An agent's test build is often signed ad-hoc, which macOS treats as a new app on every build, so
        // reading the API keys asked for the Keychain password on every test run.
        guard !isHostingTests else { return application.run() }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    /// Whether xcodebuild launched this process to host the test bundle.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let updater = Updater(preferences: .shared)
    private lazy var session = ChatSession(preferences: preferences)
    private let whatsNew = WhatsNew()
    private let updateNotice = UpdateNotice()
    private let shortcutSetup = ShortcutSetup()
    /// The `meraline://` routes being run, so the next ones wait their turn.
    private var routing: Task<Void, Never>?
    private lazy var panel: PanelController = PanelController(session: session, preferences: preferences, whatsNew: whatsNew, updater: updater, updateNotice: updateNotice, shortcutSetup: shortcutSetup) { [weak self] pane in
        self?.panel.close()
        self?.settings.show(pane)
    }
    private lazy var settings = SettingsWindowController(preferences: preferences, updater: updater, session: session)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Meraline \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber)) launched")
        CrashNotice.shared.checkForCrash()
        ChatWorkspace.removeStale()
        NSApp.mainMenu = makeMainMenu()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggleBringingSelection() }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        observeMenuBarPreference()
        MCPServerRegistry.shared.refreshAll(preferences)
        shortcutSetup.onChangeShortcut = { [weak self] in
            self?.panel.close()
            self?.settings.show(.general)
            self?.settings.focusShortcutRecorder()
        }

        let defaults = UserDefaults.meraline
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            defaults.set(true, forKey: "hasLaunchedBefore")
            defaults.set(Bundle.main.shortVersion, forKey: "lastRunVersion")
            // Before the shortcut is ever pressed: ⌥ Space may already belong to another app.
            shortcutSetup.presentIfNeeded()
            panel.show()
        } else {
            announceUpdate()
        }
    }

    /// The `meraline://` scheme. See AutomationRoute for the routes. They run one after another, in the order
    /// they came, each once the one before has its screenshot.
    func application(_ application: NSApplication, open urls: [URL]) {
        let routes = urls.compactMap { url in
            let route = AutomationRoute(url: url)
            if route == nil { Log.app.error("Ignored unknown URL route: \(url.host() ?? url.absoluteString)") }
            return route
        }
        let previous = routing
        routing = Task {
            await previous?.value
            for route in routes { await open(route) }
        }
    }

    private func open(_ route: AutomationRoute) async {
        switch route {
        case .ask(let text, let selection, let clipboard, let screen, let mode, let send):
            var with: [String] = []
            if text != nil { with.append("text") }
            if selection != nil { with.append("a selection") }
            if clipboard { with.append("the clipboard") }
            if screen { with.append("the screen") }
            Log.app.info("URL route: ask\(with.isEmpty ? "" : " with \(with.joined(separator: ", "))")\(mode.map { " in \($0.title)" } ?? "")\(send ? ", send" : "")")
            if let mode { switchMode(to: mode) }
            panel.show()
            if let selection = selection.flatMap({ SelectedText($0) }) { session.bring(selection) }
            if let text { session.draft = text }
            // A question about the screen isn't asked without the screenshot.
            let isComplete = await panel.addContext(clipboard: clipboard, screen: screen)
            if send, isComplete {
                session.send()
            } else if send {
                Log.app.info("URL route: ask not sent, some of its context couldn’t be added")
            }
        case .newChat:
            Log.app.info("URL route: new chat")
            session.reset()
            panel.show()
        case .play(let game):
            Log.app.info("URL route: play\(game.map { " \($0.title)" } ?? ", showing the games")")
            guard let game else { return panel.showGames() }
            panel.show()
            session.startGame(game)
        case .mode(let mode):
            let mode = mode ?? (preferences.mode == .llm ? .agent : .llm)
            Log.app.info("URL route: mode \(mode.title)")
            switchMode(to: mode)
            panel.show()
        case .settings(let name):
            let pane = name.flatMap(SettingsPane.init(named:))
            Log.app.info("URL route: settings\(pane.map { " on \($0.title)" } ?? "")")
            panel.close()
            settings.show(pane)
        }
    }

    /// Switches between LLM and Agent, as the toggle under the input does.
    private func switchMode(to mode: ProviderKind) {
        guard mode != preferences.mode else { return }
        preferences.mode = mode
        session.prewarm()
    }

    /// Services › Ask Meraline, in the app where text, files, or a picture are selected: they come into the
    /// window as with the shortcut, without the Accessibility access the shortcut needs, and a picture is
    /// attached as an image. Declared as `NSServices` in project.yml.
    @objc func askAboutSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        switch ClipboardContent.readSelection(from: pasteboard) {
        case .files(let files):
            Log.app.info("Services: Ask Meraline, \(files.count) file(s) or folder(s)")
            session.bring(files: Array(files.prefix(SelectionReader.fileLimit)), deliberately: true)
        case .image(let image):
            Log.app.info("Services: Ask Meraline, an image")
            session.bring(image)
        case .text(let text):
            let app = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0 }
            guard let selection = SelectedText(text, appName: app?.localizedName, appURL: app?.bundleURL) else { return }
            Log.app.info("Services: Ask Meraline, \(selection.text.count) characters")
            session.bring(selection)
        case nil:
            return
        }
        panel.show()
    }

    /// After an update, the panel offers the notes Sparkle carried for the running version, or a
    /// link to the release when it was installed by hand, until they are dismissed. Nothing is
    /// announced on a fresh install.
    private func announceUpdate() {
        let defaults = UserDefaults.meraline
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
        LiveAgents.shared.endAll()
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
