import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Meraline

/// Stash Draft (⌘S): what an empty chat has typed and added waits in Recent Chats, under the same 30 minutes as
/// any chat there, and comes back into the input when reopened.
@MainActor
struct StashDraftTests {
    private typealias Support = GameTestSupport
    private let folder = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.stash.\(UUID().uuidString)")

    private func file(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        if name.hasSuffix(".png") {
            let bitmap = try #require(Support.image().tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        } else {
            try Data(name.utf8).write(to: url)
        }
        return url
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func context(_ session: ChatSession) -> PanelContext {
        PanelContext(session: session, preferences: Support.preferences(), layout: PanelLayout(), openSettings: { _ in })
    }

    @Test func stashingParksTheDraftAndWhatWasAddedInRecentChats() throws {
        let session = Support.session(ScriptedModel())
        session.draft = "What does this say?"
        session.bring(try #require(SelectedText("Periwinkle", appName: "Safari")))
        session.attach(Support.image())
        session.attach(fileAt: try file("notes.txt"))
        #expect(session.canStashDraft)

        session.stashDraft()
        #expect(session.draft.isEmpty)
        #expect(session.draftSelections.isEmpty)
        #expect(session.draftImages.isEmpty)
        #expect(session.draftFiles.isEmpty)
        #expect(session.turns.isEmpty)
        #expect(session.expiresAt == nil, "the empty chat left behind has no time")

        let stash = try #require(session.history.first)
        #expect(session.history.count == 1)
        #expect(stash.title == "What does this say?")
        #expect(stash.turns.isEmpty)
        #expect(stash.draft?.selections.map(\.text) == ["Periwinkle"])
        #expect(stash.draft?.images.count == 1)
        #expect(stash.draft?.files.map(\.name) == ["notes.txt"])
        #expect(stash.byteCount >= (stash.draft?.images.first?.data.count ?? .max), "its pictures count in the diagnostics")
        #expect(abs(stash.expiresAt.timeIntervalSinceNow - ChatSession.chatLifetime) < 5)
        cleanUp()
    }

    @Test func aStashWithoutTextIsNamedByWhatItHolds() throws {
        let session = Support.session(ScriptedModel())
        session.bring(try #require(SelectedText("A line from Safari", appName: "Safari")))
        session.stashDraft()
        #expect(session.history.first?.title == "A line from Safari")
    }

    @Test func reopeningPutsItAllBackInTheInput() async throws {
        let model = ScriptedModel(["It says periwinkle."])
        let session = Support.session(model)
        let selection = try #require(SelectedText("Periwinkle", appName: "Safari"))
        session.draft = "What does this say?"
        session.bring(selection)
        session.attach(Support.image())
        session.stashDraft()

        session.reopen(try #require(session.history.first).id)
        #expect(session.history.isEmpty)
        #expect(session.draft == "What does this say?")
        #expect(session.draftSelections == [selection])
        #expect(session.draftImages.count == 1)
        #expect(session.turns.isEmpty)
        #expect(session.expiresAt == nil, "what is typed has no time of its own")

        session.send()
        await Support.settle(session)
        #expect(session.turns.first?.question == "What does this say?")
        #expect(session.turns.first?.selections == [selection])
        #expect(session.turns.first?.images.count == 1)
        #expect(session.turns.first?.answer == "It says periwinkle.")
    }

    @Test func aStashRunsOutOfTimeLikeAnyRecentChat() throws {
        let session = Support.session(ScriptedModel())
        session.draft = "Later"
        session.stashDraft()
        let stash = try #require(session.history.first)

        session.expireChats(now: stash.expiresAt.addingTimeInterval(-1))
        #expect(session.history.count == 1)
        session.expireChats(now: stash.expiresAt)
        #expect(session.history.isEmpty)

        var late = stash
        late.expiresAt = .now.addingTimeInterval(-1)
        session.reopen(late)
        #expect(session.draft.isEmpty, "a stash whose time is up goes instead of reopening")
    }

    @Test func onlyAnEmptyChatWithSomethingInItsDraftStashes() async {
        let session = Support.session(ScriptedModel(["Paris."]))
        #expect(!session.canStashDraft, "nothing to stash")
        session.draft = "   "
        #expect(!session.canStashDraft, "nor only spaces")

        session.isAnonymous = true
        session.draft = "Secret"
        #expect(!session.canStashDraft, "anonymous mode keeps drafts out of Recent Chats")
        session.stashDraft()
        #expect(session.history.isEmpty)
        #expect(session.draft == "Secret")
        session.isAnonymous = false

        await Support.play("Capital of France?", in: session)
        session.draft = "And of Spain?"
        #expect(!session.canStashDraft, "a follow-up belongs with its chat")

        session.reset()
        session.startGame(.wordFootball)
        session.draft = "apple"
        #expect(!session.canStashDraft, "nor a game's move")
    }

    @Test func reopeningAnotherChatStashesWhatIsTypedInAnEmptyOne() async throws {
        let session = Support.session(ScriptedModel(["Paris."]))
        await Support.play("Capital of France?", in: session)
        session.reset()
        session.draft = "Typed, not sent"

        session.reopen(try #require(session.history.first).id)
        #expect(session.turns.map(\.question) == ["Capital of France?"])
        #expect(session.draft.isEmpty)
        #expect(session.history.map(\.title) == ["Typed, not sent"])

        // Two stashes trade places.
        session.reset()
        session.draft = "Second"
        let first = try #require(session.history.first { $0.title == "Typed, not sent" })
        session.reopen(first.id)
        #expect(session.draft == "Typed, not sent")
        #expect(session.history.map(\.title) == ["Second", "Capital of France?"])
    }

    @Test func whatComesBackFromAStashStaysThroughTheNextSelection() throws {
        let session = Support.session(ScriptedModel())
        session.bringCurrentSelection(text: nil, files: [try file("photo.png")])
        #expect(session.draftImages.count == 1)
        session.stashDraft()
        session.reopen(try #require(session.history.first).id)
        #expect(session.draftImages.count == 1)

        // The shortcut again, with nothing selected: only what that selection brought would go.
        session.bringCurrentSelection(text: nil, files: [])
        #expect(session.draftImages.count == 1)
        cleanUp()
    }

    @Test func commandSStashesInAnEmptyChat() throws {
        let session = Support.session(ScriptedModel())
        let context = context(session)
        let stash = { context.action(forKeyCode: UInt16(kVK_ANSI_S), characters: "s", modifiers: .command) }
        #expect(stash() == nil, "nothing to stash")
        #expect(context.historyMenu.actions.isEmpty)

        session.draft = "Later"
        let action = try #require(stash())
        #expect(action.id == "stashDraft")
        #expect(context.historyMenu.actions.map(\.id) == ["stashDraft", "newChat"])
        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_S), characters: "S", modifiers: [.shift, .command]) == nil, "⇧⌘S is the screenshot")

        context.run(action, in: .chat, fromShortcut: true)
        #expect(session.draft.isEmpty)
        #expect(context.layout.stashNotice == 1)
        let row = try #require(context.historyMenu.actions.first)
        #expect(row.title == "Later")
        #expect(row.subtitle == "Stashed draft")
        #expect(context.historyMenu.actions.map(\.id) == [row.id, "clearHistory"])
        #expect(stash() == nil, "nothing left to stash")
    }

    @Test func commandNClearsAnEmptyChatsDraftAndStashesTheContextCardsText() throws {
        let session = Support.session(ScriptedModel())
        let context = context(session)
        let new = { context.action(forKeyCode: UInt16(kVK_ANSI_N), characters: "n", modifiers: .command) }
        #expect(new() == nil, "nothing to clear")

        // A line in the input alone goes, as it does on Esc.
        session.draft = "Later"
        var action = try #require(new())
        #expect(action.id == "newChat" && action.subtitle == "Clear what is typed and added")
        #expect(context.historyMenu.actions.map(\.id) == ["stashDraft", "newChat"])
        context.run(action, in: .chat, fromShortcut: true)
        #expect(session.draft.isEmpty && session.history.isEmpty && context.layout.stashNotice == 0)

        // The Context card's text is worth keeping: the draft goes to Recent Chats as a stash, Live off or on.
        session.writeState()
        session.typedState = "Important notes"
        session.draft = "Is this urgent?"
        action = try #require(new())
        #expect(action.subtitle == "Stash the draft in Recent Chats and start over")
        context.run(action, in: .chat, fromShortcut: true)
        #expect(session.typedState == nil && session.draft.isEmpty)
        #expect(context.layout.stashNotice == 1)
        let stash = try #require(session.history.first)
        #expect(stash.isStash && stash.draft?.typedState == "Important notes" && stash.draft?.text == "Is this urgent?")
        session.reopen(stash)
        #expect(session.typedState == "Important notes" && session.draft == "Is this urgent?")
        let stashes = session.history.count

        // With nothing in the input, ⌘N still closes the card and stashes its text; anonymous mode clears without a stash.
        session.draft = ""
        context.run(try #require(new()), in: .chat, fromShortcut: true)
        #expect(session.typedState == nil && session.history.count == stashes + 1 && context.layout.stashNotice == 2)
        session.writeState()
        session.typedState = "Secret"
        session.isAnonymous = true
        context.run(try #require(new()), in: .chat, fromShortcut: true)
        #expect(session.typedState == nil && session.history.count == stashes + 1 && context.layout.stashNotice == 2)
        #expect(new() == nil, "nothing left to clear")
    }

    @Test func aNewChatTakesTheContextCardsTextWithTheOpenChat() async throws {
        let session = Support.session(ScriptedModel(["Paris."]))
        await Support.play("Capital of France?", in: session)
        session.writeState()
        session.typedState = "Notes for the follow-up"
        #expect(!session.reset(), "with the chat, not on its own")
        let chat = try #require(session.history.first)
        #expect(!chat.isStash && chat.draft?.typedState == "Notes for the follow-up")
        #expect(session.typedState == nil)
    }
}
