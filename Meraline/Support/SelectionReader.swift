import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation

/// Reads what is selected in the app in front, for the shortcut to bring into the window: text, or the files
/// and folders selected in Finder. It must run before the window takes the keyboard, while that app still has it.
///
/// Most Mac apps share their selection through Accessibility, Finder included: its selected icons and rows
/// carry their file's URL. An app that doesn't, such as a browser or an Electron app, is asked to copy it with
/// the Copy command in its own menu (a menu command, so an app with nothing to copy doesn't beep), and the
/// clipboard is put back as it was straight after. An app that describes nothing but its window, such as Zed,
/// gets ⌘C instead when its menu won't do. Nothing is read from Meraline itself, from a password field,
/// or while secure input is on, and nothing at all without Accessibility access (see `SelectionAccess`).
enum SelectionReader {
    /// What the shortcut found selected.
    enum Found: Equatable {
        case text(SelectedText)
        /// Files and folders, as selected in Finder.
        case files([URL])

        var text: SelectedText? {
            if case .text(let text) = self { text } else { nil }
        }

        var files: [URL] {
            if case .files(let urls) = self { urls } else { [] }
        }
    }

    /// The most selected files that come along, so ⌘A in a big folder stays quick.
    static let fileLimit = 100
    /// How long an app may take to answer one Accessibility request. A busy app answers nothing.
    private static let messagingTimeout: Float = 0.25
    /// How long to wait for the Copy command to reach the clipboard. Electron apps copy a beat late.
    private static let copyWait: Duration = .milliseconds(150)
    /// ⌘C goes through the window server first.
    private static let typedCopyWait: Duration = .milliseconds(250)

    static func read() async -> Found? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var answer = selection(in: element)
        var method = "Accessibility"
        if case .unknown(let opaque) = answer {
            (answer, method) = await copySelection(in: element, typing: opaque)
        }
        switch answer {
        case .text(let text):
            guard let selection = SelectedText(text, appName: app.localizedName, appURL: app.bundleURL) else { return nil }
            Log.panel.info("Selection read through \(method), \(selection.text.count) characters")
            return .text(selection)
        case .files(let urls):
            Log.panel.info("Selection read through \(method), \(urls.count) file(s) or folder(s)")
            return .files(urls)
        case .nothing, .unknown:
            return nil
        }
    }

    private enum Answer: Equatable {
        case text(String)
        case files([URL])
        /// The app says nothing is selected, or is too busy to say.
        case nothing
        /// The app doesn't share its selection this way. `opaque` when it describes nothing but the window,
        /// as Zed does.
        case unknown(opaque: Bool)
    }

    /// The selected text of the focused element, or the files selected in it, as the app reports them.
    private static func selection(in app: AXUIElement) -> Answer {
        let (focused, focusError) = app.value(of: kAXFocusedUIElementAttribute)
        guard focusError == .success, let focused = focused.flatMap(AXUIElement.cast) else {
            return focusError == .cannotComplete ? .nothing : .unknown(opaque: false)
        }
        if focused.string(of: kAXSubroleAttribute) == kAXSecureTextFieldSubrole { return .nothing }
        let (selected, error) = focused.value(of: kAXSelectedTextAttribute)
        if error == .cannotComplete { return .nothing }
        if error == .success, let text = selected as? String, !text.trimmed.isEmpty { return .text(text) }
        let files = selectedFiles(in: focused)
        if !files.isEmpty { return .files(files) }
        return error == .success ? .nothing : .unknown(opaque: focused.string(of: kAXRoleAttribute) == kAXWindowRole)
    }

    /// The files and folders selected in a file browser such as Finder: the selected items of its desktop,
    /// grid, list, or column, each with its file's URL on it or on something inside it.
    private static func selectedFiles(in element: AXUIElement) -> [URL] {
        let items = element.elements(of: kAXSelectedChildrenAttribute) + element.elements(of: kAXSelectedRowsAttribute)
        var urls: [URL] = []
        for item in items where urls.count < fileLimit {
            if let url = fileURL(in: item, depth: 2), !urls.contains(url) { urls.append(url) }
        }
        return urls
    }

    private static func fileURL(in element: AXUIElement, depth: Int) -> URL? {
        if let url = element.value(of: kAXURLAttribute).value as? URL, url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard depth > 0 else { return nil }
        for child in element.children {
            if let url = fileURL(in: child, depth: depth - 1) { return url }
        }
        return nil
    }

    /// Asks the app to copy its selection, reads what it copied, and puts the clipboard back, saying how it
    /// asked. The Copy command in its menu comes first. An app that describes nothing but its window (`typing`)
    /// gets ⌘C when that command is missing or looks unavailable: Zed's menu says Copy is off until the menu
    /// is opened. Other apps never get a keystroke, so one with nothing to copy doesn't beep. Copied files are
    /// the selection, as in Finder; the line an editor copies when nothing is selected is not.
    private static func copySelection(in app: AXUIElement, typing: Bool) async -> (Answer, String) {
        let menuItem = copyMenuItem(in: app).flatMap { $0.value(of: kAXEnabledAttribute).value as? Bool == false ? nil : $0 }
        guard menuItem != nil || typing else { return (.nothing, "") }
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let saved = snapshot(of: pasteboard)
        let method: String
        let wait: Duration
        if let menuItem, AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success {
            (method, wait) = ("the app's Copy command", copyWait)
        } else if typing, pressCopyShortcut() {
            (method, wait) = ("⌘C", typedCopyWait)
        } else {
            return (.nothing, "")
        }

        let clock = ContinuousClock()
        let deadline = clock.now + wait
        while pasteboard.changeCount == before, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard pasteboard.changeCount != before else {
            // A Copy that lands after the wait still takes the clipboard, so it goes back when that happens.
            Task { await restoreAfterLateCopy(saved, changedFrom: before, on: pasteboard) }
            return (.nothing, method)
        }
        defer { restore(saved, to: pasteboard) }
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty { return (.files(Array(files.prefix(fileLimit))), method) }
        if isCopyOfEmptySelection(pasteboard) { return (.nothing, method) }
        return (pasteboard.string(forType: .string).map(Answer.text) ?? .nothing, method)
    }

    /// Presses ⌘C in the app in front with the key that types "c" alongside ⌘ in the current layout, so a
    /// Dvorak keyboard presses its own C. The keys carry ⌘ alone, whatever is still held from the shortcut.
    private static func pressCopyShortcut() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = keyCode(typing: "c") ?? CGKeyCode(kVK_ANSI_C)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    /// The key that types `character` with ⌘ held in the keyboard layout shortcuts use, which is the ASCII one
    /// when the current input source is, say, Russian. Nil when the layout has no such key.
    static func keyCode(typing character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let command = UInt32((cmdKey >> 8) & 0xFF)
        return data.withUnsafeBytes { bytes -> CGKeyCode? in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), command, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters
                )
                if status == noErr, String(utf16CodeUnits: characters, count: length).lowercased() == String(character) {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    /// The menu item for ⌘C in the first menus of the app's menu bar, where Edit is. Reading a menu through
    /// Accessibility doesn't open it.
    private static func copyMenuItem(in app: AXUIElement) -> AXUIElement? {
        guard let menuBar = app.value(of: kAXMenuBarAttribute).value.flatMap(AXUIElement.cast) else { return nil }
        // The Apple menu comes first and never has Copy.
        for title in menuBar.children.dropFirst().prefix(6) {
            for menu in title.children {
                for item in menu.children {
                    let key = item.string(of: kAXMenuItemCmdCharAttribute)?.lowercased()
                    // 0 is ⌘ alone; the other bits add ⇧, ⌥, and ⌃, or take ⌘ away.
                    let modifiers = item.value(of: kAXMenuItemCmdModifiersAttribute).value as? Int
                    if key == "c", modifiers == 0 { return item }
                }
            }
        }
        return nil
    }

    /// VS Code and Zed, and editors built on them, copy the current line when nothing is selected, and say so
    /// beside the text. VS Code's `vscode-editor-data` says `isFromEmptySelection`; Chromium keeps it inside
    /// its bundle of web formats, as UTF-16. Zed's `zed-metadata` says `is_entire_line` for each cursor, which
    /// it also says of a line-wise selection in its Vim mode, so that is left out too.
    static func isCopyOfEmptySelection(_ pasteboard: NSPasteboard) -> Bool {
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("vscode-editor-data")),
           let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return info["isFromEmptySelection"] as? Bool == true
        }
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("org.chromium.web-custom-data")),
           let marker = #""isFromEmptySelection":true"#.data(using: .utf16LittleEndian),
           data.range(of: marker) != nil {
            return true
        }
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("zed-metadata")),
           let json = try? JSONSerialization.jsonObject(with: data) {
            let cursors = json as? [[String: Any]] ?? (json as? [String: Any]).map { [$0] } ?? []
            return !cursors.isEmpty && cursors.allSatisfy { $0["is_entire_line"] as? Bool == true }
        }
        return false
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    /// Watches the clipboard for a second after the wait for a Copy ran out, and puts it back if the Copy
    /// arrives after all, as a busy app's may.
    private static func restoreAfterLateCopy(_ items: [NSPasteboardItem], changedFrom before: Int, on pasteboard: NSPasteboard) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(1)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                Log.panel.info("A late Copy reached the clipboard; put it back")
                restore(items, to: pasteboard)
                return
            }
        }
    }
}

/// Whether Meraline may read the selection: Accessibility access, which you give in System Settings ›
/// Privacy & Security › Accessibility. Until then, a hint in the panel says what the shortcut can bring,
/// until its cross puts it away.
@Observable
final class SelectionAccess {
    static let shared = SelectionAccess()

    private(set) var isGranted = AXIsProcessTrusted()
    var isHintDismissed = UserDefaults.standard.bool(forKey: "selectionHintDismissed") {
        didSet { UserDefaults.standard.set(isHintDismissed, forKey: "selectionHintDismissed") }
    }

    private init() {
        // System Settings announces changes to the Accessibility list; the answer can lag a moment behind.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                SelectionAccess.shared.refresh()
            }
        }
    }

    func refresh() {
        let granted = AXIsProcessTrusted()
        guard granted != isGranted else { return }
        isGranted = granted
        Log.app.info("Accessibility access \(granted ? "granted" : "withdrawn")")
    }

    /// Starts over: takes Meraline out of the Accessibility list, then shows the system's own request, which
    /// puts this copy back in it, ready to switch on.
    ///
    /// The list shows one switch per app, but macOS keeps it for the code signature that asked first. Another
    /// build of Meraline with the same bundle identifier, such as a Debug build or the test host, leaves a
    /// switch that looks on and still refuses this copy. Only Meraline's own entry is reset, and only while it
    /// doesn't work, so nothing that was allowed is lost.
    func request() {
        guard !AXIsProcessTrusted() else { return }
        Log.app.info("Asking for Accessibility access")
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.meldiron.meraline"
        Task {
            await Task.detached {
                let reset = Process()
                reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                reset.arguments = ["reset", "Accessibility", bundleIdentifier]
                reset.standardOutput = FileHandle.nullDevice
                reset.standardError = FileHandle.nullDevice
                do {
                    try reset.run()
                    reset.waitUntilExit()
                } catch {
                    Log.app.error("Couldn’t reset Accessibility access: \(error.localizedDescription)")
                }
            }.value
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }
}

private extension AXUIElement {
    static func cast(_ value: CFTypeRef) -> AXUIElement? {
        CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! AXUIElement) : nil
    }

    /// An attribute's value, or the error the app answered with.
    func value(of attribute: String) -> (value: CFTypeRef?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        return (value, error)
    }

    func string(of attribute: String) -> String? {
        value(of: attribute).value as? String
    }

    var children: [AXUIElement] {
        elements(of: kAXChildrenAttribute)
    }

    func elements(of attribute: String) -> [AXUIElement] {
        value(of: attribute).value as? [AXUIElement] ?? []
    }
}
