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
        #expect(ids(menu) == ["copyAnswer", "copyConversation", "askAgain", "newChat", "deleteChat"])
        #expect(menu?.actions.last?.confirmation != nil)
        #expect(menu?.actions.last?.isDestructive == true)
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
        await Support.settle(session)
        #expect(session.isYourMove)
        let menu = context(session).chatMenu
        #expect(menu?.title == "Rhyme Duel")
        #expect(menu?.primary?.id == (session.canHint ? "hint" : "endGame"))
        #expect(ids(menu).contains("endGame"))
        #expect(ids(menu).last == "deleteGame")
        #expect(!ids(menu).contains("askAgain"))
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
        #expect(ids(menu).contains("switchMode"))
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
        let other = menu.actions.first { $0.id == "switchMode" }
        #expect(other?.title == "Switch to Agent")
        #expect(other?.shortcut == .command("2"))
        other?.perform()
        #expect(preferences.mode == .agent)
        let agents = context(session, preferences: preferences).providersMenu
        #expect(agents.title == "Agents")
        #expect(ids(agents).contains("setUp"), "no agent is turned on in the test preferences")
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
        await Support.settle(session)
        #expect(!session.canAskAgain)
    }
}
