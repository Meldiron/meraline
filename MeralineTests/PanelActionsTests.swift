import Carbon.HIToolbox
import Foundation
import Testing
@testable import Meraline

@MainActor
struct PanelActionsTests {
    private typealias Support = GameTestSupport

    private func context(_ session: ChatSession, preferences: Preferences? = nil, settings: @escaping (SettingsPane?) -> Void = { _ in }) -> PanelContext {
        PanelContext(session: session, preferences: preferences ?? Support.preferences(), layout: PanelLayout(), openSettings: settings)
    }

    /// A session whose provider never finishes answering, so it stays streaming.
    private func streamingSession() -> ChatSession {
        ChatSession(preferences: Support.preferences()) { _ in AsyncThrowingStream { _ in } }
    }

    private func ids(_ menu: ActionMenu?) -> [String] {
        menu?.actions.map(\.id) ?? []
    }

    // MARK: Shortcuts

    @Test func keycapsFollowTheMenuOrder() {
        #expect(ActionShortcut.command("c", [.shift, .option]).keycaps == ["⌥", "⇧", "⌘", "C"])
        #expect(ActionShortcut(.delete, [.command, .shift]).keycaps == ["⇧", "⌘", "⌫"])
        #expect(ActionShortcut.escape.keycaps == ["esc"])
        #expect(ActionShortcut.returnKey.text == "↵")
    }

    @Test func aShortcutMatchesOnlyItsOwnModifiers() {
        let copyAnswer = ActionShortcut.command("c", .shift)
        #expect(copyAnswer.matches(keyCode: UInt16(kVK_ANSI_C), characters: "C", modifiers: [.shift, .command]))
        #expect(!copyAnswer.matches(keyCode: UInt16(kVK_ANSI_C), characters: "C", modifiers: [.shift, .command, .option]))
        #expect(!copyAnswer.matches(keyCode: UInt16(kVK_ANSI_C), characters: "c", modifiers: .command))
        // Letters go by what they type, so ⌘Z on a German keyboard is the key labelled Z.
        #expect(ActionShortcut.command("z").matches(keyCode: UInt16(kVK_ANSI_Y), characters: "z", modifiers: .command))
        let delete = ActionShortcut(.delete, [.command, .shift])
        #expect(delete.matches(keyCode: UInt16(kVK_Delete), characters: "\u{7F}", modifiers: [.command, .shift]))
        #expect(!delete.matches(keyCode: UInt16(kVK_Delete), characters: "\u{7F}", modifiers: .command))
        #expect(!ActionShortcut.escape.matches(keyCode: UInt16(kVK_Escape), characters: "\u{1B}", modifiers: []))
    }

    @Test func zeroIsADigitMatchedByTheKeysPlace() {
        let zero = ActionShortcut.command(digit: 0)
        #expect(zero.keycaps == ["⌘", "0"])
        #expect(zero.matches(keyCode: UInt16(kVK_ANSI_0), characters: "0", modifiers: .command))
        #expect(zero.matches(keyCode: UInt16(kVK_ANSI_0), characters: "é", modifiers: .command), "the key where a Czech keyboard types é")
        #expect(zero.matches(keyCode: UInt16(kVK_ANSI_Keypad0), characters: "0", modifiers: .command))
        #expect(!zero.matches(keyCode: UInt16(kVK_ANSI_0), characters: "0", modifiers: [.command, .shift]), "Shift makes it another shortcut")
        #expect(!zero.matches(keyCode: UInt16(kVK_ANSI_1), characters: "0", modifiers: .command))
        #expect(!ActionShortcut.command(digit: 1).matches(keyCode: UInt16(kVK_ANSI_0), characters: "1", modifiers: .command))
    }

    // MARK: The chat's actions

    @Test func noChatNoActions() {
        let context = context(Support.session(ScriptedModel()))
        #expect(context.chatMenu == nil)
        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_N), characters: "n", modifiers: .command) == nil)
    }

    @Test func anAnswerOffersCopyFirst() async {
        let session = Support.session(ScriptedModel(["Paris."]))
        await Support.play("Capital of France?", in: session)
        let menu = context(session).chatMenu
        #expect(menu?.title == "Capital of France?")
        #expect(menu?.marksPrimary == true)
        #expect(menu?.primary?.id == "copyAnswer")
        #expect(ids(menu) == ["copyAnswer", "copyConversation", "tearOff", "askAgain"] + Rewrite.allCases.map { "rewrite.\($0.rawValue)" }
            + PromptPreset.defaults(in: .english).map { "preset.\($0.id)" } + ["zoomIn", "zoomOut", "newChat", "deleteChat"])
        #expect(menu?.actions.last?.confirmation != nil)
        #expect(menu?.actions.last?.isDestructive == true)
    }

    @Test func codeInTheAnswerCanBeCopiedBlockByBlock() async throws {
        let session = Support.session(ScriptedModel(["Try:\n\n```sh\nls -la\n```\n\nor\n\n```\npwd\n```"]))
        await Support.play("List files", in: session)
        let menu = context(session).chatMenu
        let rows = menu?.actions.filter { $0.id.hasPrefix("copyCode.") } ?? []
        #expect(rows.map(\.title) == ["Copy Code Block 1", "Copy Code Block 2"])
        #expect(rows.map(\.subtitle) == ["sh · ls -la", "pwd"])
        #expect(menu?.filtered(by: "snippet").flatMap(\.actions).map(\.id) == ["copyCode.0", "copyCode.1"])
    }

    @Test func tearOffIsCommandT() async throws {
        let session = Support.session(ScriptedModel(["Step one, then step two."]))
        await Support.play("How?", in: session)
        let tearOff = try #require(context(session).action(forKeyCode: UInt16(kVK_ANSI_T), characters: "t", modifiers: .command))
        #expect(tearOff.id == "tearOff")
    }

    @Test func askAgainWithAnotherProviderMakesItTheOneInUse() async throws {
        let preferences = Support.preferences()
        preferences[.ollama] = ProviderSettings(model: "qwen3", baseURL: "http://127.0.0.1:11434", apiKey: "", isEnabled: true)
        preferences.provider = .custom
        let model = ScriptedModel(["Paris.", "Paris, on the Seine."])
        let session = ChatSession(preferences: preferences) { model.stream($0) }
        await Support.play("Capital of France?", in: session)
        let context = context(session, preferences: preferences)
        let again = try #require(context.chatMenu?.actions.first { $0.id == "askAgainWith.ollama" })
        #expect(again.title == "Ask Again with Ollama")
        #expect(context.chatMenu?.actions.contains { $0.id == "askAgainWith.custom" } == false, "not the provider in use")
        context.run(again, in: .chat)
        await Support.settle(session)
        #expect(preferences.activeProvider == .ollama)
        #expect(model.requests.last?.provider == .ollama)
        #expect(session.turns.map(\.answer) == ["Paris, on the Seine."])
    }

    @Test func whileAnsweringStopComesFirst() {
        let session = streamingSession()
        session.draft = "Tell me a story"
        session.send()
        #expect(session.isStreaming)
        let menu = context(session).chatMenu
        #expect(menu?.primary?.id == "stop")
        #expect(menu?.primary?.shortcut == .escape)
        #expect(!ids(menu).contains("askAgain"))
        #expect(ids(menu).contains("newChat"))
    }

    @Test func aGameOffersItsOwnActions() async {
        let session = Support.session(ScriptedModel(["A cat sat waiting by the door | floor, more, four"]))
        session.startGame(.rhymeDuel)
        #expect(ids(context(session).chatMenu).contains("endGame"), "a game has its actions before anyone moves")
        #expect(!ids(context(session).chatMenu).contains("restartGame"), "nothing to restart yet")
        session.send()
        await Support.settle(session)
        #expect(session.isYourMove)
        let menu = context(session).chatMenu
        #expect(menu?.title == "Rhyme Duel")
        #expect(menu?.primary?.id == (session.canHint ? "hint" : "endGame"))
        #expect(ids(menu).contains("endGame"))
        #expect(ids(menu).last == "deleteGame")
        #expect(!ids(menu).contains("askAgain"))
    }

    @Test func commandRRestartsAGameGoingOnAndPlaysAgainOnceItIsOver() async throws {
        let model = ScriptedModel(["OK: apple", "OK: egg"])
        let session = Support.session(model)
        #expect(!ids(context(session).chatMenu).contains("restartGame"), "no game to restart")
        session.startGame(.wordFootball)
        #expect(!ids(context(session).chatMenu).contains("restartGame"), "nothing to restart before the kickoff")
        await Support.play("banana", in: session)
        let context = context(session)
        let restart = try #require(context.action(forKeyCode: UInt16(kVK_ANSI_R), characters: "r", modifiers: .command))
        #expect(restart.id == "restartGame")
        #expect(restart.title == "Restart Word Football")
        context.run(restart, in: .chat, fromShortcut: true)
        #expect(session.game == .wordFootball)
        #expect(session.turns.isEmpty, "the new match waits for a kickoff")
        #expect(session.history.first?.mode == .game(.wordFootball), "the match so far is in Recent Chats")

        await Support.play("banana", in: session)
        session.draft = "pass"
        session.send()
        #expect(ids(self.context(session).chatMenu).contains("playAgain"))
        #expect(!ids(self.context(session).chatMenu).contains("restartGame"))
    }

    @Test func aShortcutRunsTheChatsAction() async throws {
        let session = Support.session(ScriptedModel(["Paris."]))
        await Support.play("Capital of France?", in: session)
        let context = context(session)
        let action = context.action(forKeyCode: UInt16(kVK_ANSI_N), characters: "n", modifiers: .command)
        #expect(action?.id == "newChat")
        context.run(try #require(action), in: .chat, fromShortcut: true)
        #expect(session.turns.isEmpty)
        #expect(session.history.map(\.title) == ["Capital of France?"])
        #expect(context.layout.actionPanel == nil)
    }

    @Test func deletingAsksFirstAndSkipsRecentChats() async throws {
        let session = Support.session(ScriptedModel(["Paris."]))
        await Support.play("Capital of France?", in: session)
        let context = context(session)
        let delete = try #require(context.action(forKeyCode: UInt16(kVK_Delete), characters: "\u{7F}", modifiers: [.command, .shift]))
        context.run(delete, in: .chat, fromShortcut: true)
        #expect(context.layout.actionPanel == ActionPanelRequest(kind: .chat, confirming: "deleteChat", isConfirmationOnly: true))
        #expect(session.turns.count == 1, "nothing is deleted before the yes")
        context.confirm(delete)
        #expect(context.layout.actionPanel == nil)
        #expect(session.turns.isEmpty)
        #expect(session.history.isEmpty)
    }

    @Test func deletingAnAgentsChatRemovesItsFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.delete.\(UUID().uuidString)")
        defer { ChatWorkspace.removeAll(in: root) }
        let preferences = Support.preferences(withProvider: false)
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.mode = .agent
        let model = ScriptedModel(["Done."])
        let session = ChatSession(preferences: preferences, workspaceRoot: root) { model.stream($0) }
        await Support.play("Write notes.md", in: session)
        let workspace = try #require(session.workspace)
        let context = context(session, preferences: preferences)
        #expect(context.chatMenu?.actions.contains { $0.id == "showWorkspace" } == true)
        #expect(context.chatMenu?.actions.last?.confirmation?.message.contains("files its agent made") == true)
        session.deleteChat()
        #expect(!FileManager.default.fileExists(atPath: workspace.url.path))
        #expect(session.history.isEmpty)
    }

    @Test func escapeBacksOutOfAConfirmation() {
        let layout = PanelLayout()
        layout.actionPanel = ActionPanelRequest(kind: .history, confirming: "clearHistory")
        layout.cancelActionPanel()
        #expect(layout.actionPanel == ActionPanelRequest(kind: .history))
        layout.cancelActionPanel()
        #expect(layout.actionPanel == nil)

        layout.actionPanel = ActionPanelRequest(kind: .chat, confirming: "deleteChat", isConfirmationOnly: true)
        let focus = layout.focusRequest
        layout.cancelActionPanel()
        #expect(layout.actionPanel == nil, "a confirmation opened by its shortcut closes")
        #expect(layout.focusRequest == focus + 1, "the input gets the keyboard back")
    }

    @Test func searchingFiltersTheRows() async {
        let session = Support.session(ScriptedModel(["Paris."]))
        await Support.play("Capital of France?", in: session)
        let menu = context(session).chatMenu
        #expect(menu?.filtered(by: "copy").flatMap(\.actions).map(\.id) == ["copyAnswer", "copyConversation"])
        #expect(menu?.filtered(by: "  ").count == menu?.sections.count)
        #expect(menu?.filtered(by: "zebra").isEmpty == true)
    }

    // MARK: The sparkle's actions

    @Test func theSparkleListsTheModesProviders() {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        var opened: [SettingsPane?] = []
        let menu = context(session, preferences: preferences) { opened.append($0) }.providersMenu
        #expect(menu.title == "LLMs")
        let custom = menu.actions.first { $0.id == "provider.custom" }
        #expect(custom?.isChecked == true)
        #expect(custom?.subtitle == "games")
        #expect(ids(menu).contains("switchMode.agent"))
        #expect(ids(menu).contains("switchMode.decision"))
        let anonymous = menu.actions.first { $0.id == "anonymous" }
        #expect(anonymous?.isChecked == false)
        anonymous?.perform()
        #expect(session.isAnonymous)
        menu.actions.first { $0.id == "settings" }?.perform()
        #expect(opened.count == 1)
    }

    @Test func switchingModeFromTheSparkle() {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences) { _ in AsyncThrowingStream { _ in } }
        let menu = context(session, preferences: preferences).providersMenu
        let other = menu.actions.first { $0.id == "switchMode.agent" }
        #expect(other?.title == "Switch to Agent")
        #expect(other?.shortcut == .command(digit: 2), "by the key's place, as the window matches it")
        other?.perform()
        #expect(preferences.mode == .agent)
        let agents = context(session, preferences: preferences).providersMenu
        #expect(agents.title == "Agents")
        #expect(ids(agents).contains("setUp"), "no agent is turned on in the test preferences")
    }

    // MARK: The mode toggle's keys

    /// ⌘ and a key as the window's key monitor hands it over: the key's code, and what the layout types there.
    private func key(_ keyCode: Int, typing characters: String, in context: PanelContext) -> PanelAction? {
        context.action(forKeyCode: UInt16(keyCode), characters: characters, modifiers: .command)
    }

    @Test func commandDigitsSwitchModesByTheKeysPlace() throws {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in AsyncThrowingStream { _ in } }
        let context = context(session, preferences: preferences)
        // A Czech keyboard types + ě š on the keys of 1 2 3, and the digits only with Shift.
        let agent = try #require(key(kVK_ANSI_2, typing: "ě", in: context))
        #expect(agent.id == "switchMode.agent")
        #expect(agent.shortcut?.keycaps == ["⌘", "2"])
        context.run(agent, in: .chat, fromShortcut: true)
        #expect(preferences.mode == .agent)
        context.run(try #require(key(kVK_ANSI_3, typing: "š", in: context)), in: .chat, fromShortcut: true)
        #expect(preferences.mode == .decision)
        context.run(try #require(key(kVK_ANSI_1, typing: "+", in: context)), in: .chat, fromShortcut: true)
        #expect(preferences.mode == .llm)
        #expect(key(kVK_ANSI_Keypad3, typing: "3", in: context)?.id == "switchMode.decision")

        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_2), characters: "2", modifiers: [.command, .shift]) == nil, "⇧⌘ and the key is another shortcut")
        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_2), characters: "ě", modifiers: []) == nil)
        #expect(key(kVK_ANSI_4, typing: "č", in: context) == nil, "three modes, three keys")
        #expect(key(kVK_ANSI_W, typing: "2", in: context) == nil, "a 2 typed by another key isn't the key")
    }

    @Test func everyModeSwitchesToEveryOther() throws {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in AsyncThrowingStream { _ in } }
        let context = context(session, preferences: preferences)
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3]
        for from in ProviderKind.allCases {
            for (to, keyCode) in zip(ProviderKind.allCases, keys) {
                preferences.mode = from
                // The mode in use has its key too, which changes nothing, so the key never reaches the input.
                let action = try #require(key(keyCode, typing: "", in: context), "\(from) to \(to)")
                context.run(action, in: .chat, fromShortcut: true)
                #expect(preferences.mode == to, "\(from) to \(to)")
            }
        }
    }

    @Test func aModesKeyIsThePresetsWhileTheyHoldIt() async throws {
        let preferences = Support.preferences()
        let model = ScriptedModel(["Paris."])
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        let context = context(session, preferences: preferences)
        #expect(key(kVK_ANSI_2, typing: "ě", in: context)?.id == "switchMode.agent", "an empty chat")
        await Support.play("Capital of France?", in: session)

        // Four presets by default, so they hold all three of the modes' digits once the answer is ready.
        let second = preferences.presets[1]
        #expect(key(kVK_ANSI_2, typing: "ě", in: context)?.id == "preset.\(second.id)")
        #expect(context.modeSwitches.allSatisfy { $0.shortcut == nil })
        #expect(context.providersMenu.actions.first { $0.id == "switchMode.agent" }?.shortcut == nil, "the sparkle's row says so too")

        // With two presets, ⌘3 stays the mode's.
        preferences.presets = Array(preferences.presets.prefix(2))
        #expect(key(kVK_ANSI_2, typing: "ě", in: context)?.id == "preset.\(second.id)")
        let decision = try #require(key(kVK_ANSI_3, typing: "š", in: context))
        #expect(decision.id == "switchMode.decision")
        #expect(context.providersMenu.actions.first { $0.id == "switchMode.decision" }?.shortcut == .command(digit: 3))
        context.run(decision, in: .chat, fromShortcut: true)
        #expect(preferences.mode == .decision)
    }

    @Test func modesSwitchWhileAnAnswerIsComingAndWithAPanelOpen() throws {
        let preferences = Support.preferences()
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in AsyncThrowingStream { _ in } }
        session.draft = "Tell me a story"
        session.send()
        #expect(session.isStreaming)
        let context = context(session, preferences: preferences)
        #expect(context.chatMenu != nil, "a chat with no answer ready")
        let agent = try #require(key(kVK_ANSI_2, typing: "ě", in: context))
        #expect(agent.id == "switchMode.agent")

        // With a panel of actions open, the key closes it and switches, as the chat's shortcuts do.
        for kind in [ActionPanelKind.chat, .providers, .history] {
            preferences.mode = .llm
            context.layout.actionPanel = ActionPanelRequest(kind: kind)
            context.run(try #require(key(kVK_ANSI_2, typing: "ě", in: context)), in: .chat, fromShortcut: true)
            #expect(preferences.mode == .agent)
            #expect(context.layout.actionPanel == nil)
        }
    }

    @Test func modesSwitchInAGame() async throws {
        let preferences = Support.preferences()
        let model = ScriptedModel(["OK: apple"])
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        session.startGame(.wordFootball)
        await Support.play("banana", in: session)
        let context = context(session, preferences: preferences)
        #expect(key(kVK_ANSI_2, typing: "ě", in: context)?.id == "switchMode.agent")
    }

    @Test func theKeyWhereACzechKeyboardTypesPlusIsCommandOneNotZoomIn() async throws {
        // An answer to zoom, and a follow-up still coming, so no preset holds ⌘1.
        let preferences = Support.preferences()
        let model = ScriptedModel(["Paris."])
        var asked = 0
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { request in
            asked += 1
            return asked == 1 ? model.stream(request) : AsyncThrowingStream { _ in }
        }
        await Support.play("Capital of France?", in: session)
        session.draft = "And of Spain?"
        session.send()
        #expect(session.isStreaming)
        preferences.mode = .agent
        let context = context(session, preferences: preferences)
        #expect(context.canZoomAnswers)
        #expect(key(kVK_ANSI_1, typing: "+", in: context)?.id == "switchMode.llm")
        #expect(key(kVK_ANSI_Equal, typing: "=", in: context)?.id == "zoomIn", "⌘= zooms on any keyboard")
        #expect(key(kVK_ANSI_KeypadPlus, typing: "+", in: context)?.id == "zoomIn", "as does the keypad's +")
    }

    // MARK: Recent chats

    @Test func recentChatsReopenAndClearAfterAsking() async throws {
        let session = Support.session(ScriptedModel(["One", "Two"]))
        await Support.play("First?", in: session)
        session.reset()
        await Support.play("Second?", in: session)
        session.reset()
        let context = context(session)
        let menu = context.historyMenu
        #expect(menu.actions.map(\.title) == ["Second?", "First?", "Clear Recent Chats"])
        let clear = try #require(menu.actions.last)
        #expect(clear.confirmation?.title == "Clear 2 recent chats?")
        context.run(clear, in: .history)
        #expect(context.layout.actionPanel?.confirming == "clearHistory")
        #expect(session.history.count == 2)
        context.confirm(clear)
        #expect(session.history.isEmpty)
        #expect(context.layout.lastForgetting?.count == 2)

        let empty = context.historyMenu
        #expect(empty.actions.isEmpty)
        #expect(empty.emptyText.hasPrefix("No recent chats"))
    }

    @Test func aRecentChatReopens() async throws {
        let session = Support.session(ScriptedModel(["One"]))
        await Support.play("First?", in: session)
        session.reset()
        let context = context(session)
        let chat = try #require(context.historyMenu.actions.first)
        context.run(chat, in: .history)
        #expect(session.turns.first?.question == "First?")
        #expect(session.history.isEmpty)
    }

    // MARK: Ask Again

    @Test func askAgainReplacesTheLastAnswerAndKeepsTheInput() async {
        let model = ScriptedModel(["One", "Two"])
        let session = Support.session(model)
        await Support.play("Pick a number", in: session)
        session.draft = "half a follow-up"
        #expect(session.canAskAgain)
        session.askAgain()
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["Two"])
        #expect(session.draft == "half a follow-up")
        #expect(model.lastMessages == ["Pick a number"], "the old answer is not part of the new question")
    }

    @Test func aFailedAskAgainBringsTheOldAnswerBack() async {
        let session = Support.session(ScriptedModel(["One"]))
        await Support.play("Pick a number", in: session)
        session.draft = "typing"
        session.askAgain()
        await Support.settle(session)
        #expect(session.turns.map(\.answer) == ["One"])
        #expect(session.turns.first?.isComplete == true)
        #expect(session.draft == "typing")
        #expect(session.failure != nil)
    }

    @Test func gamesCannotAskAgain() async {
        let session = Support.session(ScriptedModel(["A cat sat waiting by the door | floor, more, four"]))
        session.startGame(.rhymeDuel)
        session.send()
        await Support.settle(session)
        #expect(!session.canAskAgain)
    }
}
