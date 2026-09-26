import AppKit
import KeyboardShortcuts
import Testing
@testable import Meraline

struct ShortcutSetupTests {
    private typealias Shortcut = KeyboardShortcuts.Shortcut

    private let controlOptionSpace = Shortcut(.space, modifiers: [.control, .option])
    private let optionCommandSpace = Shortcut(.space, modifiers: [.option, .command])
    private let controlShiftSpace = Shortcut(.space, modifiers: [.control, .shift])

    @Test func aShortcutMacOSUsesComesFirst() {
        #expect(ShortcutConflict.check(isRegistered: false, isTakenBySystem: true, rivals: ["Raycast"]) == .system)
    }

    @Test func aShortcutThatFailedToRegisterIsTaken() {
        #expect(ShortcutConflict.check(isRegistered: false, isTakenBySystem: false, rivals: ["Raycast"]) == .taken)
    }

    @Test func appsOnThisMacMakeAGuess() {
        let conflict = ShortcutConflict.check(isRegistered: true, isTakenBySystem: false, rivals: ["ChatGPT", "Raycast"])
        #expect(conflict == .apps(["ChatGPT", "Raycast"]))
        #expect(conflict?.isGuess == true)
        #expect(ShortcutConflict.taken.isGuess == false)
    }

    @Test func aRegisteredShortcutNoAppUsesIsFree() {
        #expect(ShortcutConflict.check(isRegistered: true, isTakenBySystem: false, rivals: []) == nil)
    }

    @Test func rivalsAreFoundRunningOrInstalled() {
        let rivals = ShortcutRival.matching(
            runningIdentifiers: ["com.raycast.macos", "com.apple.finder"],
            runningNames: ["Raycast", "Finder"],
            isInstalled: { $0 == "com.google.GeminiMacOS" }
        )
        #expect(rivals.map(\.name) == ["Gemini", "Raycast"])
    }

    @Test func aRivalWithoutAKnownIdentifierIsFoundByName() {
        let rivals = ShortcutRival.matching(runningIdentifiers: ["com.example.seer"], runningNames: ["Seer"], isInstalled: { _ in false })
        #expect(rivals.map(\.name) == ["Seer"])
    }

    @Test func nothingIsFoundOnACleanMac() {
        let rivals = ShortcutRival.matching(runningIdentifiers: ["com.apple.finder"], runningNames: ["Finder"], isInstalled: { _ in false })
        #expect(rivals.isEmpty)
    }

    @Test func theSentenceAgreesWithHowManyApps() {
        #expect(ShortcutRival.sentence(naming: ["Raycast"]) == "Raycast is")
        #expect(ShortcutRival.sentence(naming: ["ChatGPT", "Raycast"]) == "ChatGPT and Raycast are")
    }

    @Test func suggestionsStartWithOptionShiftSpace() {
        let picked = ShortcutSuggestion.pick(avoiding: .optionSpace) { _ in false }
        #expect(picked.map(\.shortcut) == [.optionShiftSpace, controlOptionSpace, optionCommandSpace])
    }

    @Test func suggestionsSkipWhatMacOSOrAnAppUses() {
        // A stock Mac: ⌃⌥ Space switches input sources and ⌥⌘ Space opens a Finder search. Gemini also takes ⌥⇧ Space.
        let taken: Set<Shortcut> = [controlOptionSpace, optionCommandSpace, .optionShiftSpace]
        let picked = ShortcutSuggestion.pick(avoiding: .optionSpace) { taken.contains($0) }
        #expect(picked.map(\.shortcut) == [controlShiftSpace, Shortcut(.space, modifiers: [.shift, .command])])
    }

    @Test func suggestionsNeverOfferTheShortcutInQuestion() {
        let picked = ShortcutSuggestion.pick(avoiding: .optionShiftSpace) { _ in false }
        #expect(!picked.map(\.shortcut).contains(.optionShiftSpace))
        #expect(picked.count == 3)
    }

    @MainActor
    @Test func keysAreWrittenOnePerKeycap() {
        #expect(Shortcut.optionSpace.keys == ["⌥", "Space"])
        #expect(controlOptionSpace.keys == ["⌃", "⌥", "Space"])
        #expect(Shortcut.optionShiftSpace.spokenKeys == "⌥ ⇧ Space")
        #expect(Shortcut(.k, modifiers: [.command, .shift]).keys == ["⇧", "⌘", "K"])
    }
}
