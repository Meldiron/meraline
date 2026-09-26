import AppKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    /// A shortcut the picker holds for a moment, so it can be pressed before Meraline keeps it.
    static let shortcutTrial = Self("shortcutTrial")
}

extension KeyboardShortcuts.Shortcut {
    nonisolated static let optionSpace = Self(.space, modifiers: [.option])
    nonisolated static let optionShiftSpace = Self(.space, modifiers: [.option, .shift])

    /// The keys to press, one per keycap, in the order macOS writes them: ⌃ ⌥ ⇧ ⌘, then the key.
    var keys: [String] {
        let modifiers = modifiers.ks_symbolicRepresentation.map(String.init)
        let key = String(description.dropFirst(modifiers.count))
        return modifiers + (key.isEmpty ? [] : [key])
    }

    /// The shortcut in a sentence, a space between its keys, such as ⌥ Space.
    var spokenKeys: String { keys.joined(separator: " ") }
}

/// An app that takes ⌥ Space, or a shortcut Meraline might suggest instead, out of the box.
nonisolated struct ShortcutRival: Equatable, Sendable {
    let name: String
    let bundleIdentifiers: [String]
    let shortcuts: [KeyboardShortcuts.Shortcut]

    static let all: [ShortcutRival] = [
        ShortcutRival(name: "ChatGPT", bundleIdentifiers: ["com.openai.chat", "com.openai.codex"], shortcuts: [.optionSpace]),
        ShortcutRival(name: "Gemini", bundleIdentifiers: ["com.google.GeminiMacOS"], shortcuts: [.optionSpace, .optionShiftSpace]),
        ShortcutRival(name: "Copilot", bundleIdentifiers: ["com.microsoft.copilot-mac"], shortcuts: [.optionSpace]),
        ShortcutRival(name: "Raycast", bundleIdentifiers: ["com.raycast.macos"], shortcuts: [.optionSpace]),
        ShortcutRival(name: "Alfred", bundleIdentifiers: ["com.runningwithcrayons.Alfred"], shortcuts: [.optionSpace]),
        ShortcutRival(name: "SpotAsk", bundleIdentifiers: ["com.spotask.app"], shortcuts: [.optionSpace]),
        // Known by name only, while it runs.
        ShortcutRival(name: "Seer", bundleIdentifiers: [], shortcuts: [.optionSpace]),
    ]

    /// The rivals on this Mac: running, found by bundle identifier or by name, or installed where Launch
    /// Services can find them.
    static func matching(
        runningIdentifiers: Set<String>,
        runningNames: Set<String>,
        isInstalled: (String) -> Bool,
        among rivals: [ShortcutRival] = all
    ) -> [ShortcutRival] {
        rivals.filter { rival in
            runningNames.contains(rival.name)
                || rival.bundleIdentifiers.contains { runningIdentifiers.contains($0) || isInstalled($0) }
        }
    }

    /// Says which of them usually take a shortcut, such as “Raycast is” or “ChatGPT and Raycast are”.
    static func sentence(naming names: [String]) -> String {
        "\(names.formatted(.list(type: .and))) \(names.count == 1 ? "is" : "are")"
    }
}

/// Why a shortcut might not reach Meraline.
nonisolated enum ShortcutConflict: Equatable, Sendable {
    /// macOS uses it for one of its own shortcuts, such as Spotlight or switching input sources.
    case system
    /// Registering it failed, so another app holds it.
    case taken
    /// Apps that usually take it are on this Mac. macOS gives it to whichever registered it last.
    case apps([String])

    static func check(isRegistered: Bool, isTakenBySystem: Bool, rivals: [String]) -> ShortcutConflict? {
        if isTakenBySystem { return .system }
        if !isRegistered { return .taken }
        return rivals.isEmpty ? nil : .apps(rivals)
    }

    /// A guess from the apps on this Mac rather than something Meraline knows, so keeping the shortcut anyway
    /// is offered.
    var isGuess: Bool {
        if case .apps = self { true } else { false }
    }
}

/// A shortcut the picker offers instead, with a line on where the keys are.
nonisolated struct ShortcutSuggestion: Identifiable, Equatable, Sendable {
    let shortcut: KeyboardShortcuts.Shortcut
    let hint: String

    var id: KeyboardShortcuts.Shortcut { shortcut }

    /// In the order they are offered. The first that nothing seems to use is the recommended one.
    static let candidates: [ShortcutSuggestion] = [
        ShortcutSuggestion(shortcut: .optionShiftSpace, hint: "Same hand as ⌥ Space, one extra key"),
        ShortcutSuggestion(shortcut: .init(.space, modifiers: [.control, .option]), hint: "⌃ and ⌥ sit side by side, left of the space bar"),
        ShortcutSuggestion(shortcut: .init(.space, modifiers: [.option, .command]), hint: "Spotlight’s ⌘ Space, with ⌥ beside it"),
        ShortcutSuggestion(shortcut: .init(.space, modifiers: [.control, .shift]), hint: "Both keys on the left edge, one above the other"),
        ShortcutSuggestion(shortcut: .init(.space, modifiers: [.shift, .command]), hint: "Spotlight’s ⌘ Space, with ⇧ added"),
    ]

    /// The first few candidates that are not the shortcut in question and that nothing else seems to use.
    static func pick(avoiding current: KeyboardShortcuts.Shortcut, count: Int = 3, isTaken: (KeyboardShortcuts.Shortcut) -> Bool) -> [ShortcutSuggestion] {
        Array(candidates.filter { $0.shortcut != current && !isTaken($0.shortcut) }.prefix(count))
    }
}

/// The shortcut picker in the window on the first launch, before the shortcut has ever been pressed, and the
/// capsule under the input when the picker was put away without a choice.
///
/// ⌥ Space is crowded: ChatGPT, Gemini, Copilot, Raycast, and Alfred use it out of the box, and macOS gives it
/// to whichever app registered it last, so the other looks broken. The picker checks the shortcut first:
/// whether macOS uses it, whether Meraline could register it, and which apps that usually take it are on this
/// Mac. Then it offers to keep it, or suggests others. A suggestion is registered for a moment under
/// `shortcutTrial`, and pressing it keeps it. Put away with Esc or a click elsewhere, the picker leaves the
/// shortcut as it was and a capsule under the input offers to change it, until it is changed or dismissed.
@Observable
final class ShortcutSetup {
    enum Step: Equatable {
        /// The shortcut looks free: keep it, or pick another.
        case offer
        /// The suggestions, and a recorder for a shortcut of your own.
        case pick
        /// A shortcut held for a moment, waiting to be pressed.
        case trial(KeyboardShortcuts.Shortcut)
        /// The shortcut on trial was pressed. The picker folds away in a moment.
        case worked(KeyboardShortcuts.Shortcut)
    }

    /// Set once the picker has been answered or put away. The first launch shows it unless this is set.
    static let chosenKey = "hasChosenShortcut"
    private static let noticeKey = "shortcutNotice"
    /// How long a trial waits for a press before it says another app may be holding the shortcut.
    private static let quietAfter: Duration = .seconds(6)

    private(set) var isPresented = false
    private(set) var step: Step = .offer
    /// Meraline's shortcut when the picker opened. It stays until another is chosen.
    private(set) var current: KeyboardShortcuts.Shortcut = .optionSpace
    private(set) var conflict: ShortcutConflict?
    private(set) var suggestions: [ShortcutSuggestion] = []
    /// Why the last shortcut tried can't be used.
    private(set) var problem: String?
    /// The trial has waited a while without a press.
    private(set) var isTrialQuiet = false
    /// The capsule under the input, offering to change a shortcut that may not work.
    private(set) var showsNotice = false

    /// Opens Settings › General on the shortcut recorder.
    @ObservationIgnored var onChangeShortcut: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var quietTimer: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsNotice = noticeShortcut != nil
        forgetNoticeIfChanged()
        // KeyboardShortcuts posts this, under this name, whenever a shortcut is set through it, Settings included.
        changeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forgetNoticeIfChanged() }
        }
    }

    /// Shows the picker, unless it was answered before.
    func presentIfNeeded() {
        guard !defaults.bool(forKey: Self.chosenKey) else { return }
        present()
    }

    func present() {
        current = KeyboardShortcuts.getShortcut(for: .togglePanel) ?? .optionSpace
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications
        let rivals = ShortcutRival.matching(
            runningIdentifiers: Set(running.compactMap(\.bundleIdentifier)),
            runningNames: Set(running.compactMap(\.localizedName)),
            isInstalled: { workspace.urlForApplication(withBundleIdentifier: $0) != nil }
        )
        conflict = ShortcutConflict.check(
            isRegistered: KeyboardShortcuts.isEnabled(for: .togglePanel),
            isTakenBySystem: current.isTakenBySystem,
            rivals: rivals.filter { $0.shortcuts.contains(current) }.map(\.name)
        )
        suggestions = ShortcutSuggestion.pick(avoiding: current) { shortcut in
            shortcut.isTakenBySystem || rivals.contains { $0.shortcuts.contains(shortcut) }
        }
        step = conflict == nil ? .offer : .pick
        problem = nil
        isTrialQuiet = false
        isPresented = true
        listen()
        Log.app.info("Shortcut picker: \(current.description) \(conflict.map(Self.describe) ?? "looks free"), suggesting \(suggestions.map(\.shortcut.description).joined(separator: " "))")
    }

    /// Keeps the shortcut Meraline has.
    func keep() {
        Log.app.info("Shortcut picker: kept \(current.description)")
        finish()
    }

    func pickAnother() {
        step = .pick
        problem = nil
    }

    /// Registers a shortcut for a moment, for a press to show it works. One that macOS uses, or that another app
    /// holds, comes back with the reason.
    func tryShortcut(_ shortcut: KeyboardShortcuts.Shortcut) {
        problem = nil
        if shortcut.isTakenBySystem {
            KeyboardShortcuts.setShortcut(nil, for: .shortcutTrial)
            problem = "macOS uses \(shortcut.spokenKeys) for one of its own shortcuts. Pick another."
            return
        }
        KeyboardShortcuts.setShortcut(shortcut, for: .shortcutTrial)
        guard KeyboardShortcuts.isEnabled(for: .shortcutTrial) else {
            KeyboardShortcuts.setShortcut(nil, for: .shortcutTrial)
            problem = "Another app already holds \(shortcut.spokenKeys). Pick another."
            Log.app.info("Shortcut picker: \(shortcut.description) could not be registered")
            return
        }
        step = .trial(shortcut)
        isTrialQuiet = false
        quietTimer?.cancel()
        quietTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.quietAfter)
            guard !Task.isCancelled, let self, self.step == .trial(shortcut) else { return }
            self.isTrialQuiet = true
        }
    }

    /// Back from a trial to the suggestions.
    func tryAnother() {
        endTrial()
        step = .pick
    }

    /// Makes a shortcut Meraline's, pressed or not.
    func use(_ shortcut: KeyboardShortcuts.Shortcut) {
        if shortcut != current {
            KeyboardShortcuts.setShortcut(shortcut, for: .togglePanel)
        }
        Log.app.info("Shortcut picker: chose \(shortcut.description)")
        finish()
    }

    /// Esc or a click elsewhere: the shortcut stays as it was, and the capsule under the input offers to change it.
    func dismiss() {
        guard isPresented else { return }
        Log.app.info("Shortcut picker: put away, keeping \(current.description)")
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Self.noticeKey)
            showsNotice = true
        }
        finish()
    }

    func changeShortcut() {
        onChangeShortcut?()
    }

    func dismissNotice() {
        defaults.removeObject(forKey: Self.noticeKey)
        showsNotice = false
    }

    private func finish() {
        guard isPresented else { return }
        endTrial()
        listener?.cancel()
        listener = nil
        defaults.set(true, forKey: Self.chosenKey)
        isPresented = false
    }

    private func endTrial() {
        quietTimer?.cancel()
        quietTimer = nil
        isTrialQuiet = false
        problem = nil
        KeyboardShortcuts.setShortcut(nil, for: .shortcutTrial)
    }

    /// Waits for the shortcut on trial. The stream is there for as long as the picker is, so each trial only
    /// swaps the shortcut under `shortcutTrial`.
    private func listen() {
        guard listener == nil else { return }
        let presses = KeyboardShortcuts.events(.keyUp, for: .shortcutTrial)
        listener = Task { [weak self] in
            for await _ in presses {
                self?.trialPressed()
            }
        }
    }

    private func trialPressed() {
        guard case .trial(let shortcut) = step else { return }
        quietTimer?.cancel()
        isTrialQuiet = false
        step = .worked(shortcut)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, self.step == .worked(shortcut) else { return }
            self.use(shortcut)
        }
    }

    private var noticeShortcut: KeyboardShortcuts.Shortcut? {
        defaults.data(forKey: Self.noticeKey).flatMap { try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: $0) }
    }

    /// The capsule goes once the shortcut it warns about is no longer Meraline's.
    private func forgetNoticeIfChanged() {
        guard showsNotice, noticeShortcut != KeyboardShortcuts.getShortcut(for: .togglePanel) else { return }
        dismissNotice()
    }

    private static func describe(_ conflict: ShortcutConflict) -> String {
        switch conflict {
        case .system: "is a macOS shortcut"
        case .taken: "could not be registered"
        case .apps(let names): "may be taken by \(names.joined(separator: ", "))"
        }
    }
}
