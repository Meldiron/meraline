import Carbon.HIToolbox
import Foundation
import Testing
@testable import Meraline

/// The presets of Settings › Prompt in the chat's actions once an answer is ready, the first nine on ⌘1…⌘9, each
/// run on the answer as a rewrite.
@MainActor
struct PresetShortcutTests {
    private typealias Support = GameTestSupport

    /// A chat whose actions and questions share one set of preferences, so a test can change its presets.
    private struct Chat {
        let session: ChatSession
        let preferences: Preferences
        let model: ScriptedModel
        var context: PanelContext {
            PanelContext(session: session, preferences: preferences, layout: PanelLayout(), openSettings: { _ in })
        }
    }

    private func chat(_ replies: [String] = [], answering: Bool = true) -> Chat {
        let preferences = Support.preferences()
        let model = ScriptedModel(replies)
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { request in
            answering ? model.stream(request) : AsyncThrowingStream { _ in }
        }
        return Chat(session: session, preferences: preferences, model: model)
    }

    private func presetRows(_ menu: ActionMenu?) -> [PanelAction] {
        menu?.actions.filter { $0.id.hasPrefix("preset.") } ?? []
    }

    // MARK: The keys

    @Test func aDigitGoesByTheKeysPlaceWhateverTheLayoutTypesThere() {
        let one = ActionShortcut.command(digit: 1)
        #expect(one.keycaps == ["⌘", "1"])
        #expect(one.matches(keyCode: UInt16(kVK_ANSI_1), characters: "1", modifiers: .command))
        #expect(one.matches(keyCode: UInt16(kVK_ANSI_1), characters: "+", modifiers: .command), "the key where a Czech keyboard types +")
        #expect(one.matches(keyCode: UInt16(kVK_ANSI_1), characters: "&", modifiers: .command), "and where a French one types &")
        #expect(one.matches(keyCode: UInt16(kVK_ANSI_Keypad1), characters: "1", modifiers: .command))
        #expect(!one.matches(keyCode: UInt16(kVK_ANSI_2), characters: "1", modifiers: .command), "a 1 typed by another key isn't the key")
        #expect(!one.matches(keyCode: UInt16(kVK_ANSI_1), characters: "!", modifiers: [.command, .shift]))
        #expect(!one.matches(keyCode: UInt16(kVK_ANSI_1), characters: "1", modifiers: []))
        #expect(ActionShortcut.command(digit: 9).matches(keyCode: UInt16(kVK_ANSI_9), characters: "9", modifiers: .command))
        #expect(ActionShortcut.command(digit: 9).matches(keyCode: UInt16(kVK_ANSI_Keypad9), characters: "9", modifiers: .command))
    }

    // MARK: The actions

    @Test func aReadyAnswerOffersThePresetsAfterTheRewritesOnCommandDigits() async throws {
        let chat = chat(["Paris."])
        await Support.play("Capital of France?", in: chat.session)
        let menu = try #require(chat.context.chatMenu)
        let rows = presetRows(menu)
        let presets = chat.preferences.presets
        #expect(rows.map(\.id) == presets.map { "preset.\($0.id)" })
        #expect(rows.map(\.title) == presets.map(\.title))
        #expect(rows.map { $0.shortcut?.text } == ["⌘1", "⌘2", "⌘3", "⌘4"])
        let ids = menu.actions.map(\.id)
        let firstPreset = try #require(ids.firstIndex(of: rows[0].id))
        #expect(ids[firstPreset - 1] == "rewrite.\(Rewrite.allCases.last!.rawValue)", "after the rewrites")
        #expect(ids[firstPreset + rows.count] == "zoomIn", "and ahead of the zoom")
        #expect(chat.session.presetShortcuts(among: presets) == 4, "the mode toggle gives up ⌘1 and ⌘2 meanwhile")
    }

    @Test func noPresetsBeforeAnAnswerIsReadyOrInAGame() async {
        let waiting = chat(answering: false)
        #expect(waiting.session.presetShortcuts(among: waiting.preferences.presets) == 0, "⌘1 and ⌘2 pick the mode on an empty panel")
        waiting.session.draft = "Capital of France?"
        waiting.session.send()
        #expect(waiting.session.isStreaming)
        #expect(presetRows(waiting.context.chatMenu).isEmpty, "not while the answer streams")
        #expect(waiting.session.presetShortcuts(among: waiting.preferences.presets) == 0)
        #expect(waiting.context.action(forKeyCode: UInt16(kVK_ANSI_1), characters: "1", modifiers: .command)?.id == "switchMode.llm", "the mode toggle's meanwhile")

        let game = chat(["OK: salmon"])
        game.session.startGame(.wordFootball)
        await Support.play("apple", in: game.session)
        #expect(presetRows(game.context.chatMenu).isEmpty)
        #expect(game.session.presetShortcuts(among: game.preferences.presets) == 0)
    }

    @Test func onlyTheFirstNineHaveShortcutsAndPresetsWithoutTextAreLeftOut() async {
        let chat = chat(["An answer."])
        var presets = (1...10).map { PromptPreset(id: "p\($0)", title: "Preset number \($0)", symbol: "star", text: "Do thing \($0) to this text:") }
        presets.insert(PromptPreset(id: "blank", title: "Unwritten", symbol: "star", text: "  "), at: 2)
        presets[0].title = " "
        chat.preferences.presets = presets
        await Support.play("Question?", in: chat.session)
        let rows = presetRows(chat.context.chatMenu)
        #expect(rows.map(\.id) == (1...10).map { "preset.p\($0)" }, "the one without text can't run")
        #expect(rows.first?.title == "Preset 1", "an untitled preset goes by its place")
        #expect(rows.compactMap { $0.shortcut?.text } == (1...9).map { "⌘\($0)" })
        #expect(rows.last?.shortcut == nil)
        #expect(chat.session.presetShortcuts(among: presets) == 9)
    }

    // MARK: Running one

    @Test func commandDigitRunsItsPresetOnTheAnswerInItsPlace() async throws {
        let chat = chat(["The heating is broken.", "Die Heizung ist kaputt."])
        await Support.play("Tell my landlord", in: chat.session)
        chat.session.draft = "half a follow-up"
        let translate = try #require(chat.preferences.presets.first { $0.id == "translate" })
        let action = try #require(chat.context.action(forKeyCode: UInt16(kVK_ANSI_4), characters: "4", modifiers: .command))
        #expect(action.id == "preset.translate")
        chat.context.run(action, in: .chat, fromShortcut: true)
        await Support.settle(chat.session)
        #expect(chat.session.turns.map(\.question) == ["Tell my landlord"])
        #expect(chat.session.turns.map(\.answer) == ["Die Heizung ist kaputt."])
        #expect(chat.model.lastMessages == ["Tell my landlord", "The heating is broken.", translate.instruction])
        #expect(chat.session.draft == "half a follow-up")
        #expect(chat.session.usage.allTime.rewrites == [PromptPreset.usageKey: 1], "counted as a rewrite, never by the preset's name")
        #expect(chat.context.action(forKeyCode: UInt16(kVK_ANSI_5), characters: "5", modifiers: .command) == nil, "four presets, four shortcuts")
    }

    @Test func aFailedPresetRunBringsTheOldAnswerBack() async {
        let chat = chat(["The answer."])
        await Support.play("Question?", in: chat.session)
        chat.session.run(chat.preferences.presets[0])
        await Support.settle(chat.session)
        #expect(chat.session.turns.map(\.answer) == ["The answer."])
        #expect(chat.session.failure != nil)
    }

    @Test func theInstructionIsThePresetsTextWithTheAnswerAsItsText() {
        for preset in PromptPreset.defaults(in: .english) {
            #expect(preset.instruction.hasPrefix(preset.text))
            #expect(preset.instruction.hasSuffix("The text is your last answer. Reply with only the result: no preamble, and no comment on what changed."))
        }
        #expect(PromptPreset.runnable([PromptPreset.blank()]).isEmpty)
    }
}
