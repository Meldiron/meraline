import AppKit
import Foundation
import Synchronization
import Testing
@testable import Meraline

/// The presets above an empty chat: what a click puts in the input or asks at once, what a Shift-click prepares,
/// how Settings keeps them, and that they come and go with a chat in the hidden panel without hanging it.
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

    /// The text a preset works on comes on a card of its own, so no default ends with a colon waiting for it.
    @Test func theDefaultsEndAsSentences() {
        for kind in ProviderKind.allCases {
            for preset in PromptPreset.defaults(for: kind, in: .english) {
                #expect(!preset.text.hasSuffix(":"), "\(preset.title)")
            }
        }
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

    @Test func aSecondClickTakesThePresetOutUnlessItIsSent() {
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

    @Test func aClickFillsTheInputWithoutTextAndAsksAtOnceWithTheSelection() async throws {
        let model = ScriptedModel(["Hello, how are you?"])
        let session = Support.session(model)
        session.apply(fix, among: presets)
        #expect(session.draft == "\(fix.text) ")
        #expect(session.turns.isEmpty)
        #expect(session.typedState == "", "the card opens for the text to work on")

        session.bring(try #require(SelectedText("helo how r u", appName: "Mail")))
        session.apply(translate, among: presets)
        await Support.settle(session)
        #expect(session.draft.isEmpty)
        #expect(session.typedState == nil, "the card, left empty, goes with the question and adds nothing")
        #expect(session.turns.count == 1)
        #expect(session.turns[0].question == translate.text)
        #expect(session.turns[0].selections.map(\.sourceLabel) == ["Mail"])
        let message = try #require(model.lastMessages.last)
        #expect(message.hasPrefix("<selected_text from=\"Mail\">\nhelo how r u\n</selected_text>"))
        #expect(message.hasSuffix(translate.text))
    }

    @Test func aPresetOpensTheCardForItsTextWithNothingToWorkOn() throws {
        let session = Support.session(ScriptedModel())
        #expect(session.apply(fix, among: presets), "put in with nothing to work on, it opens the card, which takes the keyboard")
        #expect(session.typedState == "")
        #expect(session.apply(translate, among: presets), "another preset finds the card open, still empty, and hands it the keyboard again")
        #expect(session.typedState == "")
        #expect(session.turns.isEmpty, "nothing was sent: the card is empty")
        #expect(!session.apply(translate, among: presets), "taken out again, it leaves the keyboard where it is")
        #expect(session.typedState == "", "and the card stays")
        #expect(PromptPreset.applied(in: session.draft, among: presets) == nil)
    }

    /// A text selected or copied, a picture, or text written on the Context card is what a preset works on, so a
    /// click asks at once instead of putting the preset in the input.
    @Test func aClickAsksAtOnceWithSomethingToWorkOn() async throws {
        let model = ScriptedModel(["Fixed.", "Fixed.", "Fixed."])
        let session = Support.session(model)
        session.bring(try #require(SelectedText("helo how r u", appName: "Mail")))
        #expect(!session.hasNoContext)
        #expect(!session.apply(fix, among: presets), "a selection is the text to work on, so the question goes")
        await Support.settle(session)
        #expect(session.turns.map(\.question) == [fix.text])
        #expect(session.turns[0].selections.map(\.sourceLabel) == ["Mail"])
        #expect(session.draft.isEmpty && session.typedState == nil)

        session.reset()
        session.bring(Support.image())
        #expect(!session.apply(fix, among: presets), "as is a picture")
        await Support.settle(session)
        #expect(session.turns.count == 1 && session.turns[0].images.count == 1)

        // Text on the Context card too: the card a click opened, written in, and the same preset clicked again
        // is sent, not taken out.
        session.reset()
        #expect(session.hasNoContext)
        #expect(session.apply(fix, among: presets))
        session.typedState = "helo how r u"
        #expect(!session.hasNoContext)
        #expect(!session.apply(fix, among: presets))
        await Support.settle(session)
        #expect(session.turns.count == 1)
        #expect(session.turns[0].question == fix.text)
        #expect(session.turns[0].selections.map(\.sourceLabel) == ["Context"])
        #expect(session.typedState == nil)
    }

    /// A Shift-click never sends: in LLM and Agent modes the preset goes in the input to add to, whatever the draft
    /// holds, and in Decision mode the Context card decides live with the preset and takes the keyboard.
    @Test func aShiftClickPutsThePresetInOrDecidesLiveWithIt() async throws {
        let session = Support.session(ScriptedModel())
        let mail = try #require(SelectedText("Production is down", appName: "Mail"))
        session.bring(mail)
        #expect(!session.prepare(fix, among: presets), "with the text to work on there, the input keeps the keyboard")
        #expect(session.draft == "\(fix.text) ")
        #expect(session.turns.isEmpty && session.typedState == nil)
        #expect(!session.prepare(fix, among: presets), "and once more takes it out")
        #expect(session.draft.isEmpty)
        session.removeSelection(mail.id)
        #expect(session.prepare(fix, among: presets), "with nothing to work on, the card opens as for a click")
        #expect(session.typedState == "")

        // Decision mode: Live on with the preset, the card open for the text, nothing in the input.
        let preferences = Support.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "sk-test", isEnabled: true)
        preferences.mode = .decision
        let asked = AskedLive()
        let model = ScriptedModel()
        let deciding = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { model.stream($0) }) { questions, _, _, _ in
            asked.ids.append(questions.map(\.id))
            return DecisionClient.LiveReply(decisions: Dictionary(uniqueKeysWithValues: questions.map { ($0.id, LiveDecisionTests.yes) }), usage: .zero)
        }
        deciding.liveDecisions.debounce = 0.04
        deciding.liveDecisions.maxWait = 0.12
        let decisions = PromptPreset.decisionDefaults
        #expect(!deciding.liveDecisions.isOn)
        #expect(deciding.prepare(decisions[0], among: decisions), "the card opens and takes the keyboard")
        #expect(deciding.typedState == "")
        #expect(deciding.liveDecisions.isOn)
        #expect(deciding.liveDecisions.enabledPresets == ["urgent"])
        #expect(deciding.draft.isEmpty, "nothing goes in the input")
        #expect(deciding.turns.isEmpty)
        #expect(deciding.prepare(decisions[2], among: decisions), "another preset joins, and Live stays on")
        #expect(deciding.liveDecisions.enabledPresets == ["urgent", "tone"])
        #expect(deciding.prepare(decisions[0], among: decisions), "once more leaves it on")
        #expect(deciding.liveDecisions.enabledPresets == ["urgent", "tone"])
        deciding.typedState = "Production is down"
        try await Task.sleep(for: .milliseconds(250))
        #expect(asked.ids.last == ["preset.urgent", "preset.tone"], "the presets are asked about the text as it is typed")
    }

    @MainActor
    private final class AskedLive {
        var ids: [[String]] = []
    }

    @Test func aGameTakesNoPreset() {
        let session = Support.session(ScriptedModel())
        session.startGame(.rhymeDuel)
        #expect(!session.apply(fix, among: presets))
        #expect(!session.prepare(fix, among: presets))
        #expect(session.draft.isEmpty)
        #expect(session.typedState == nil)
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

    @Test func aPresetMovesToItsPlaceAmongTheOthers() {
        let titles = { (list: [PromptPreset]) in list.map(\.title) }
        #expect(titles(PromptPreset.moving(presets, from: 0, to: 2)) == ["Anti-Slop", "Anonymize", "Fix Grammar", "Translate"])
        #expect(titles(PromptPreset.moving(presets, from: 3, to: 0)) == ["Translate", "Fix Grammar", "Anti-Slop", "Anonymize"])
        #expect(PromptPreset.moving(presets, from: 1, to: 1) == presets)
        #expect(PromptPreset.moving(presets, from: 9, to: 0) == presets)
        #expect(titles(PromptPreset.moving(presets, from: 0, to: 99)).last == "Fix Grammar")
    }

    /// A dragged row lands past every row whose middle its leading edge has passed, and those between make way.
    @Test func aDraggedRowLandsPastTheMiddlesItsEdgesPass() {
        let heights: [CGFloat] = [40, 40, 40, 40]
        #expect(PresetDrag.destination(from: 0, translation: 0, heights: heights) == 0)
        #expect(PresetDrag.destination(from: 0, translation: 19, heights: heights) == 0)
        #expect(PresetDrag.destination(from: 0, translation: 41, heights: heights) == 1)
        #expect(PresetDrag.destination(from: 0, translation: 120, heights: heights) == 3)
        #expect(PresetDrag.destination(from: 3, translation: -41, heights: heights) == 2)
        #expect(PresetDrag.destination(from: 3, translation: -120, heights: heights) == 0)
        #expect(PresetDrag.destination(from: 1, translation: 0, heights: [30, 60, 30]) == 1)
        #expect(PresetDrag.destination(from: 1, translation: 31, heights: [30, 60, 30]) == 2)
        // A tall row dragged as far as it goes reaches either end.
        #expect(PresetDrag.destination(from: 0, translation: PresetDrag.clamped(500, from: 0, heights: [60, 30, 30]), heights: [60, 30, 30]) == 2)
        #expect(PresetDrag.destination(from: 2, translation: PresetDrag.clamped(-500, from: 2, heights: [30, 30, 60]), heights: [30, 30, 60]) == 0)

        #expect(PresetDrag.clamped(-500, from: 1, heights: heights) == -40)
        #expect(PresetDrag.clamped(500, from: 1, heights: heights) == 80)
        #expect(PresetDrag.clamped(12, from: 1, heights: heights) == 12)

        // Dragged from the top to the third place, the two it passes move up; dragged up, they move down.
        #expect((0..<4).map { PresetDrag.shift(of: $0, from: 0, to: 2, height: 40) } == [0, -40, -40, 0])
        #expect((0..<4).map { PresetDrag.shift(of: $0, from: 3, to: 1, height: 40) } == [0, 40, 40, 0])
    }

    /// The Suggested icons are each a symbol macOS has under its current name, once.
    @Test func theSuggestedIconsAreEachOneSymbol() {
        let catalog = SymbolCatalog.shared
        let current = PromptPreset.symbols.map(catalog.current)
        #expect(Set(current).count == current.count)
        #expect(current.allSatisfy(PromptPreset.exists))
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

    @Test func thePresetsComeAndGoWithAChatWithoutHangingTheHiddenPanel() async throws {
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

        session.bring(try #require(SelectedText("their going", appName: "Mail")))
        settle("a preset is sent") { session.apply(fix, among: presets) }
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
