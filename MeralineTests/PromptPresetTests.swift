import AppKit
import Foundation
import Synchronization
import Testing
@testable import Meraline

/// The presets above an empty chat: what a click puts in the input, what a Shift-click sends, how Settings keeps
/// them, and that they come and go with a chat in the hidden panel without hanging it.
@MainActor
struct PromptPresetTests {
    private typealias Support = GameTestSupport
    private let presets = PromptPreset.defaults(in: .english)
    private var fix: PromptPreset { presets[0] }
    private var translate: PromptPreset { presets[3] }

    private static func throwaway() -> UserDefaults {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func preferences(_ defaults: UserDefaults) -> Preferences {
        Preferences(defaults: defaults, secrets: SecretStore(read: { _ in "" }, write: { _, _ in }), onDeviceModelAvailable: false)
    }

    // MARK: The input

    @Test func theDefaultsAreFourWithIconsMacOSHas() {
        #expect(presets.map(\.title) == ["Fix Grammar", "Anti-Slop", "Anonymize", "Translate"])
        #expect(presets.allSatisfy { PromptPreset.exists($0.symbol) })
        #expect(PromptPreset.symbols.allSatisfy(PromptPreset.exists))
        #expect(Set(PromptPreset.symbols).count == PromptPreset.symbols.count)
        #expect(PromptPreset.defaults(in: .czech)[3].text.contains("into Czech"))
    }

    @Test func aClickPutsThePresetAheadOfWhatWasTyped() {
        #expect(PromptPreset.draft("", applying: fix, among: presets) == "\(fix.text) ")
        #expect(PromptPreset.draft("  their going  ", applying: fix, among: presets) == "\(fix.text) their going")
    }

    @Test func anotherPresetTakesThePlaceOfTheOneInTheInput() {
        let fixed = PromptPreset.draft("bonjour", applying: fix, among: presets)
        #expect(PromptPreset.applied(in: fixed, among: presets) == fix)
        let translated = PromptPreset.draft(fixed, applying: translate, among: presets)
        #expect(translated == "\(translate.text) bonjour")
        #expect(PromptPreset.applied(in: translated, among: presets) == translate)
    }

    @Test func aSecondClickTakesThePresetOutAndAShiftClickKeepsIt() {
        let fixed = PromptPreset.draft("bonjour", applying: fix, among: presets)
        #expect(PromptPreset.draft(fixed, applying: fix, among: presets) == "bonjour")
        #expect(PromptPreset.draft(PromptPreset.draft("", applying: fix, among: presets), applying: fix, among: presets).isEmpty)
        #expect(PromptPreset.draft(fixed, applying: fix, among: presets, toggling: false) == fixed)
    }

    @Test func theLongestPresetTheInputStartsWithIsTheOneInIt() {
        let short = PromptPreset(id: "a", title: "A", symbol: "star", text: "Explain")
        let long = PromptPreset(id: "b", title: "B", symbol: "star", text: "Explain like I’m five:")
        #expect(PromptPreset.applied(in: "Explain like I’m five: rain", among: [short, long]) == long)
        #expect(PromptPreset.applied(in: "Explain rain", among: [short, long]) == short)
        #expect(PromptPreset.applied(in: "rain", among: [short, long]) == nil)
        #expect(PromptPreset.applied(in: "rain", among: [PromptPreset(id: "c", title: "C", symbol: "star", text: " ")]) == nil)
    }

    @Test func anUnknownSymbolShowsTheFallback() {
        var preset = PromptPreset.blank()
        #expect(preset.shownSymbol == PromptPreset.fallbackSymbol)
        preset.symbol = "no.such.symbol"
        #expect(preset.shownSymbol == PromptPreset.fallbackSymbol)
        preset.symbol = "star"
        #expect(preset.shownSymbol == "star")
    }

    // MARK: The chat

    @Test func aClickFillsTheInputAndAShiftClickSendsWithTheSelection() async throws {
        let model = ScriptedModel(["Hello, how are you?"])
        let session = Support.session(model)
        session.apply(fix, among: presets, sending: false)
        #expect(session.draft == "\(fix.text) ")
        #expect(session.turns.isEmpty)

        session.bring(try #require(SelectedText("helo how r u", appName: "Mail")))
        session.apply(translate, among: presets, sending: true)
        await Support.settle(session)
        #expect(session.draft.isEmpty)
        #expect(session.turns.count == 1)
        #expect(session.turns[0].question == translate.text)
        let message = try #require(model.lastMessages.last)
        #expect(message.hasPrefix("<selected_text from=\"Mail\">\nhelo how r u\n</selected_text>"))
        #expect(message.hasSuffix(translate.text))
    }

    @Test func aGameTakesNoPreset() {
        let session = Support.session(ScriptedModel())
        session.startGame(.rhymeDuel)
        session.apply(fix, among: presets, sending: false)
        #expect(session.draft.isEmpty)
    }

    // MARK: Settings

    @Test func onlyAChangedListIsKeptAndTheDefaultsFollowTheLanguage() throws {
        let defaults = Self.throwaway()
        let preferences = Self.preferences(defaults)
        #expect(preferences.presets == presets)
        #expect(!preferences.arePresetsChanged)
        preferences.language = .slovak
        #expect(preferences.presets[3].text.contains("into Slovak"))

        var changed = preferences.presets
        changed[0].title = "Grammar"
        changed.append(PromptPreset(id: "tldr", title: "TL;DR", symbol: "list.bullet", text: "Sum this up in one line:"))
        changed.remove(at: 1)
        preferences.presets = changed
        #expect(preferences.arePresetsChanged)
        #expect(defaults.data(forKey: PromptPreset.key) != nil)
        #expect(Self.preferences(defaults).presets == changed)

        preferences.presets = PromptPreset.defaults(in: .slovak)
        #expect(!preferences.arePresetsChanged)
        #expect(defaults.data(forKey: PromptPreset.key) == nil)
    }

    @Test func anEmptyListStaysEmptyAndABrokenOneGivesTheDefaults() {
        let defaults = Self.throwaway()
        Self.preferences(defaults).presets = []
        #expect(Self.preferences(defaults).presets.isEmpty)
        defaults.set(Data("not a list".utf8), forKey: PromptPreset.key)
        #expect(Self.preferences(defaults).presets == presets)
    }

    // MARK: The hidden panel

    /// Runs `body`, then the run loop for the display cycle to lay the window out as the presets animate, and
    /// ends the test run if that takes longer than `seconds`, since a hung main thread would never end it (see
    /// `AnnouncementsTests`).
    private func settle(_ step: String, within seconds: UInt32 = 10, _ body: () -> Void) {
        let done = Mutex(false)
        let watchdog = Thread {
            sleep(seconds)
            guard !done.withLock({ $0 }) else { return }
            FileHandle.standardError.write(Data("PromptPresetTests: the panel's layout never finished after \(step); ending the test run\n".utf8))
            exit(70)
        }
        watchdog.start()
        body()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        done.withLock { $0 = true }
    }

    @Test func thePresetsComeAndGoWithAChatWithoutHangingTheHiddenPanel() async {
        let defaults = Self.throwaway()
        defaults.set(true, forKey: ShortcutSetup.chosenKey) // the chat, not the shortcut picker
        let preferences = Support.preferences()
        let model = ScriptedModel(["Fixed."])
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: Updater(preferences: preferences, defaults: defaults), updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        #expect(!controller.isVisible)
        settle("the panel is made") {}

        settle("a preset is sent") { session.apply(fix, among: presets, sending: true) }
        #expect(!controller.isVisible, "sent")
        await Support.settle(session)
        settle("the answer is in") {}
        #expect(!controller.isVisible, "answered")
        #expect(session.turns.count == 1)
        settle("a new chat starts") { session.reset() }
        #expect(!controller.isVisible, "reset")
        settle("the presets change") { preferences.presets = Array(presets.prefix(2)) }
        #expect(!controller.isVisible)
    }
}
