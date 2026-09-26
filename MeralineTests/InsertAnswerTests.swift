import Carbon.HIToolbox
import Foundation
import Testing
@testable import Meraline

@MainActor
struct InsertAnswerTests {
    private typealias Support = GameTestSupport

    /// Stands in for the app in front: remembers what it was handed.
    private final class Notes {
        var inserted: [String] = []
        func insertion(canPaste: Bool = true) -> AnswerInsertion {
            AnswerInsertion(appName: "Notes", canPaste: canPaste) { self.inserted.append($0) }
        }
    }

    private func context(_ session: ChatSession, _ insertion: AnswerInsertion?) -> PanelContext {
        PanelContext(session: session, preferences: Support.preferences(), layout: PanelLayout(), openSettings: { _ in }, insertion: insertion)
    }

    private func answered() async -> ChatSession {
        let session = Support.session(ScriptedModel(["Dear team, the launch moves to Friday."]))
        await Support.play("Make this email polite", in: session)
        return session
    }

    @Test func anAnswerCanGoBackToTheAppInFront() async throws {
        let notes = Notes()
        let menu = try #require(context(await answered(), notes.insertion()).chatMenu)
        #expect(menu.actions.map(\.id).prefix(2) == ["copyAnswer", "insertAnswer"])
        let insert = try #require(menu.actions.first { $0.id == "insertAnswer" })
        #expect(insert.title == "Insert Answer into Notes")
        #expect(insert.subtitle == nil)
        #expect(insert.shortcut?.keycaps == ["⌘", "↵"])
    }

    @Test func commandReturnInsertsTheLastAnswer() async throws {
        let notes = Notes()
        let session = await answered()
        let context = context(session, notes.insertion())
        #expect(context.action(forKeyCode: UInt16(kVK_Return), characters: "\r", modifiers: []) == nil, "Return alone stays with the input")
        let action = try #require(context.action(forKeyCode: UInt16(kVK_Return), characters: "\r", modifiers: .command))
        #expect(action.id == "insertAnswer")
        context.run(action, in: .chat, fromShortcut: true)
        #expect(notes.inserted == ["Dear team, the launch moves to Friday."])
        #expect(session.turns.count == 1, "the chat stays for next time")
    }

    @Test func commandReturnLeavesAFollowUpBeingTyped() async throws {
        let session = await answered()
        session.draft = "and in German?"
        let context = context(session, Notes().insertion())
        #expect(context.action(forKeyCode: UInt16(kVK_Return), characters: "\r", modifiers: .command) == nil)
        #expect(context.chatMenu?.actions.contains { $0.id == "insertAnswer" } == true, "the row stays in Actions")
    }

    @Test func searchingForPasteFindsIt() async throws {
        let menu = try #require(context(await answered(), Notes().insertion()).chatMenu)
        #expect(menu.filtered(by: "paste").flatMap(\.actions).map(\.id) == ["insertAnswer"])
        #expect(menu.filtered(by: "cursor").flatMap(\.actions).map(\.id) == ["insertAnswer"])
    }

    @Test func withoutAccessibilityItSaysItOnlyCopies() async throws {
        let menu = try #require(context(await answered(), Notes().insertion(canPaste: false)).chatMenu)
        let insert = try #require(menu.actions.first { $0.id == "insertAnswer" })
        #expect(insert.subtitle?.contains("Accessibility") == true)
    }

    @Test func notOfferedWithoutAnAppOrAFinishedAnswer() async {
        #expect(context(await answered(), nil).chatMenu?.actions.contains { $0.id == "insertAnswer" } == false)

        let waiting = ChatSession(preferences: Support.preferences()) { _ in AsyncThrowingStream { _ in } }
        waiting.draft = "Tell me a story"
        waiting.send()
        #expect(context(waiting, Notes().insertion()).chatMenu?.actions.contains { $0.id == "insertAnswer" } == false)

        let game = Support.session(ScriptedModel(["A cat sat waiting by the door | floor, more, four"]))
        game.startGame(.rhymeDuel)
        await Support.settle(game)
        #expect(context(game, Notes().insertion()).chatMenu?.actions.contains { $0.id == "insertAnswer" } == false)
    }
}
