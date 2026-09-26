import AppKit
import Foundation
import Testing
@testable import Meraline

/// The clipboard button reads a pasteboard of the test's own, never the real clipboard.
@MainActor
struct ClipboardContentTests {
    private func pasteboard(_ write: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MeralineTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        write(pasteboard)
        return pasteboard
    }

    private func png() throws -> Data {
        let tiff = try #require(GameTestSupport.image().tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    /// One item with each kind of data in the order given, as an app that copied it would write them.
    private func item(_ entries: [(NSPasteboard.PasteboardType, Data)]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, data) in entries { item.setData(data, forType: type) }
        return item
    }

    @Test func textIsText() throws {
        let board = pasteboard { $0.setString("Hello, clipboard", forType: .string) }
        defer { board.releaseGlobally() }
        guard case .text(let text) = try #require(ClipboardContent.read(from: board)) else {
            Issue.record("Expected text")
            return
        }
        #expect(text == "Hello, clipboard")
    }

    @Test func copiedFilesAreFiles() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "MeralineClipboard-\(UUID().uuidString).txt")
        try Data("notes".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let board = pasteboard { $0.writeObjects([url as NSURL]) }
        defer { board.releaseGlobally() }
        guard case .files(let urls) = try #require(ClipboardContent.read(from: board)) else {
            Issue.record("Expected files")
            return
        }
        #expect(urls.map(\.lastPathComponent) == [url.lastPathComponent])
    }

    @Test func aPictureAloneIsAnImage() throws {
        let png = try png()
        let board = pasteboard { $0.setData(png, forType: .png) }
        defer { board.releaseGlobally() }
        guard case .image = try #require(ClipboardContent.read(from: board)) else {
            Issue.record("Expected an image")
            return
        }
    }

    @Test func aPictureCopiedBeforeItsTextStaysAPicture() throws {
        let copied = item([(.png, try png()), (.string, Data("https://example.com/cat.png".utf8))])
        let board = pasteboard { $0.writeObjects([copied]) }
        defer { board.releaseGlobally() }
        guard case .image = try #require(ClipboardContent.read(from: board)) else {
            Issue.record("Expected an image")
            return
        }
    }

    @Test func wordsCopiedBeforeAPictureStayWords() throws {
        let copied = item([(.string, Data("A paragraph".utf8)), (.png, try png())])
        let board = pasteboard { $0.writeObjects([copied]) }
        defer { board.releaseGlobally() }
        guard case .text(let text) = try #require(ClipboardContent.read(from: board)) else {
            Issue.record("Expected text")
            return
        }
        #expect(text == "A paragraph")
    }

    @Test func blankTextAndAnEmptyClipboardAreNothing() {
        let blank = pasteboard { $0.setString(" \n\t ", forType: .string) }
        let empty = pasteboard { _ in }
        defer {
            blank.releaseGlobally()
            empty.releaseGlobally()
        }
        #expect(ClipboardContent.read(from: blank) == nil)
        #expect(ClipboardContent.read(from: empty) == nil)
    }

    @Test func aPasswordIsNeverRead() {
        let board = pasteboard { board in
            board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
            board.setString("hunter2", forType: .string)
        }
        defer { board.releaseGlobally() }
        #expect(ClipboardContent.read(from: board) == nil)
        #expect(!ClipboardContent.hasContent(board))
    }

    @Test func hasContentGoesByKindsAlone() throws {
        let text = pasteboard { $0.setString("words", forType: .string) }
        let png = try png()
        let picture = pasteboard { $0.setData(png, forType: .png) }
        let empty = pasteboard { _ in }
        defer { [text, picture, empty].forEach { $0.releaseGlobally() } }
        #expect(ClipboardContent.hasContent(text))
        #expect(ClipboardContent.hasContent(picture))
        #expect(!ClipboardContent.hasContent(empty))
    }

    @Test func theFirstKnownKindDecides() {
        let custom = NSPasteboard.PasteboardType("com.example.private")
        #expect(ClipboardContent.picturesFirst([custom, .tiff, .string]))
        #expect(ClipboardContent.picturesFirst([.pdf, .string]))
        #expect(!ClipboardContent.picturesFirst([custom, .rtf, .string, .tiff]))
        #expect(!ClipboardContent.picturesFirst([.html, .png]))
        #expect(!ClipboardContent.picturesFirst([]))
    }
}

@MainActor
struct ClipboardInChatTests {
    @Test func copiedTextWaitsInACardAndGoesAsAClipboardBlock() async throws {
        let model = ScriptedModel(["Hi."])
        let session = GameTestSupport.session(model)
        let ids = session.addClipboard(.text("  Copied words \n"))
        let selection = try #require(session.draftSelections.first)
        #expect(ids == [selection.id])
        #expect(selection.text == "Copied words")
        #expect(selection.isFromClipboard)
        #expect(selection.appName == "Clipboard")

        session.draft = "Translate"
        session.send()
        await GameTestSupport.settle(session)
        #expect(model.lastMessages == ["<clipboard>\nCopied words\n</clipboard>\n\nTranslate"])
        #expect(session.turns.first?.selections.first?.isFromClipboard == true)
    }

    @Test func copiedTextJoinsSelectedTextAndComesOnce() throws {
        let session = GameTestSupport.session(ScriptedModel())
        session.bring(try #require(SelectedText("Selected", appName: "Safari")))
        let first = session.addClipboard(.text("Copied"))
        let again = session.addClipboard(.text("Copied"))
        #expect(first == again)
        #expect(session.draftSelections.map(\.text) == ["Selected", "Copied"])
        #expect(session.draftSelections.map(\.isFromClipboard) == [false, true])
    }

    @Test func theShortcutLeavesClipboardTextAlone() throws {
        let session = GameTestSupport.session(ScriptedModel())
        session.addClipboard(.text("From the clipboard"))
        session.bringCurrentSelection(text: SelectedText("Selected", appName: "Safari"), files: [])
        session.bringCurrentSelection(text: nil, files: [])
        #expect(session.draftSelections.map(\.text) == ["From the clipboard"])
    }

    @Test func copiedPicturesAddUp() {
        let session = GameTestSupport.session(ScriptedModel())
        let first = session.addClipboard(.image(GameTestSupport.image()))
        let second = session.addClipboard(.image(GameTestSupport.image()))
        #expect(session.draftImages.count == 2)
        #expect(first.count == 1 && second.count == 1 && first != second)
    }

    @Test func copiedFilesAttachAsAPasteDoesAndAreFoundAgain() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "MeralineClipboard-\(UUID().uuidString).txt")
        try Data("notes".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = GameTestSupport.session(ScriptedModel())
        let first = session.addClipboard(.files([url]))
        #expect(session.draftFiles.map(\.name) == [url.lastPathComponent])
        #expect(session.fileNotice != nil)
        #expect(session.addClipboard(.files([url])) == first)
        #expect(session.draftFiles.count == 1)
    }

    @Test func removingContextTakesOutWhatItNames() throws {
        let session = GameTestSupport.session(ScriptedModel())
        let text = session.addClipboard(.text("Copied"))
        let picture = session.addClipboard(.image(GameTestSupport.image()))
        session.removeContext(text)
        #expect(session.draftSelections.isEmpty)
        #expect(session.draftImages.count == 1)
        session.removeContext(picture)
        #expect(session.draftImages.isEmpty)
    }

    @Test func gamesTakeNothingFromTheClipboard() {
        let session = GameTestSupport.session(ScriptedModel())
        session.startGame(.categories)
        #expect(session.addClipboard(.text("Copied")).isEmpty)
        #expect(session.addClipboard(.image(GameTestSupport.image())).isEmpty)
        #expect(session.draftSelections.isEmpty)
        #expect(session.draftImages.isEmpty)
    }

    @Test func severalTextsGoInOrderBeforeTheQuestion() throws {
        let selected = try #require(SelectedText("One", appName: "Safari"))
        let copied = try #require(SelectedText.clipboard("Two"))
        #expect(SelectedText.message("Compare", about: [selected, copied]) == """
        <selected_text from="Safari">
        One
        </selected_text>

        <clipboard>
        Two
        </clipboard>

        Compare
        """)
        #expect(SelectedText.message("", about: [copied]) == "<clipboard>\nTwo\n</clipboard>")
        #expect(SelectedText.message("Plain", about: []) == "Plain")
    }
}

/// Selected text waits on offer until the selection button adds it, and the button takes it out again
/// while that very text is in the draft.
@MainActor
struct OfferedSelectionTests {
    private func selection(_ text: String = "Selected words", in app: String = "Safari") -> SelectedText {
        SelectedText(text, appName: app)!
    }

    @Test func theShortcutOnlyOffersSelectedText() {
        let session = GameTestSupport.session(ScriptedModel())
        session.bringCurrentSelection(text: selection(), files: [])
        #expect(session.draftSelections.isEmpty)
        #expect(session.offeredSelection?.text == "Selected words")
        #expect(!session.isOfferedSelectionAdded)
        #expect(!session.canSend)
    }

    @Test func theButtonAddsThenTakesOut() {
        let session = GameTestSupport.session(ScriptedModel())
        session.bringCurrentSelection(text: selection(), files: [])
        #expect(session.toggleOfferedSelection())
        #expect(session.draftSelections.map(\.text) == ["Selected words"])
        #expect(session.isOfferedSelectionAdded)
        #expect(session.toggleOfferedSelection())
        #expect(session.draftSelections.isEmpty)
        #expect(!session.isOfferedSelectionAdded)
    }

    @Test func textsFromSeveralAppsAddUp() async {
        let model = ScriptedModel(["Sure."])
        let session = GameTestSupport.session(model)
        session.bringCurrentSelection(text: selection("From Safari"), files: [])
        session.toggleOfferedSelection()
        session.withdrawOfferedSelection()
        session.bringCurrentSelection(text: selection("From Notes", in: "Notes"), files: [])
        #expect(!session.isOfferedSelectionAdded)
        session.toggleOfferedSelection()
        #expect(session.draftSelections.map(\.text) == ["From Safari", "From Notes"])

        session.draft = "Compare"
        session.send()
        await GameTestSupport.settle(session)
        #expect(model.lastMessages.first?.contains("From Safari") == true)
        #expect(model.lastMessages.first?.contains("<selected_text from=\"Notes\">\nFrom Notes") == true)
    }

    @Test func theSameTextSelectedAgainCountsAsAdded() {
        let session = GameTestSupport.session(ScriptedModel())
        session.bringCurrentSelection(text: selection(), files: [])
        session.toggleOfferedSelection()
        session.bringCurrentSelection(text: selection(), files: [])
        #expect(session.isOfferedSelectionAdded)
        session.toggleOfferedSelection()
        #expect(session.draftSelections.isEmpty)
    }

    @Test func copiedTextIsNotTheSelection() {
        let session = GameTestSupport.session(ScriptedModel())
        session.addClipboard(.text("Selected words"))
        session.bringCurrentSelection(text: selection(), files: [])
        #expect(!session.isOfferedSelectionAdded)
        session.toggleOfferedSelection()
        #expect(session.draftSelections.map(\.isFromClipboard) == [true, false])
    }

    @Test func withNothingOfferedTheButtonDoesNothing() {
        let session = GameTestSupport.session(ScriptedModel())
        #expect(!session.toggleOfferedSelection())
        session.bringCurrentSelection(text: selection(), files: [])
        session.withdrawOfferedSelection()
        #expect(!session.toggleOfferedSelection())
        #expect(session.draftSelections.isEmpty)
    }

    @Test func gamesAreOfferedNothing() {
        let session = GameTestSupport.session(ScriptedModel())
        session.startGame(.categories)
        session.bringCurrentSelection(text: selection(), files: [])
        #expect(!session.toggleOfferedSelection())
        #expect(session.draftSelections.isEmpty)
    }
}

/// Which clipboard copy and which visit to a screen each button's items came from.
@MainActor
struct ContextSourcesTests {
    private func board() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("MeralineTests.\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test func aNewCopyIsANewClipboard() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let sources = ContextSources(pasteboard: pasteboard)
        #expect(!sources.clipboardHasContent)
        let session = GameTestSupport.session(ScriptedModel())

        pasteboard.clearContents()
        pasteboard.setString("First", forType: .string)
        sources.refreshClipboard()
        #expect(sources.clipboardHasContent)
        let first = sources.clipboard
        sources.note(session.addClipboard(.text("First")), from: first, in: session)
        #expect(sources.items(from: sources.clipboard, in: session).count == 1)

        pasteboard.clearContents()
        pasteboard.setString("Second", forType: .string)
        sources.refreshClipboard()
        #expect(sources.clipboard != first)
        #expect(sources.items(from: sources.clipboard, in: session).isEmpty)
        #expect(sources.items(from: first, in: session).count == 1)
    }

    @Test func eachVisitIsANewScreen() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let sources = ContextSources(pasteboard: pasteboard)
        let session = GameTestSupport.session(ScriptedModel())
        sources.windowOpened()
        defer { sources.windowClosed() }
        let visit = sources.screen

        let before = session.draftContextIDs
        session.attach(GameTestSupport.image())
        sources.note(session.draftContextIDs.subtracting(before), from: visit, in: session)
        #expect(sources.items(from: sources.screen, in: session).count == 1)

        sources.screenChanged()
        #expect(sources.items(from: sources.screen, in: session).isEmpty)
        sources.windowOpened()
        #expect(sources.screen != visit)
        #expect(sources.items(from: visit, in: session).count == 1)
    }

    @Test func itemsThatLeaveTheDraftAreForgotten() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let sources = ContextSources(pasteboard: pasteboard)
        let session = GameTestSupport.session(ScriptedModel())
        let ids = session.addClipboard(.text("Copied"))
        sources.note(ids, from: sources.clipboard, in: session)
        session.removeContext(ids)
        #expect(sources.items(from: sources.clipboard, in: session).isEmpty)
    }
}
