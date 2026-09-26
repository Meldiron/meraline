import AppKit
import Foundation
import Testing
@testable import Meraline

struct SelectedTextTests {
    @Test func trimsTheEndsAndMakesLineBreaksPlain() throws {
        let selection = try #require(SelectedText("  \r\nfirst line\r\nsecond\rthird \n\n", appName: " Safari "))
        #expect(selection.text == "first line\nsecond\nthird")
        #expect(selection.appName == "Safari")
        #expect(!selection.isShortened)
    }

    @Test func blankTextIsNoSelection() {
        #expect(SelectedText("") == nil)
        #expect(SelectedText(" \n\t ") == nil)
        #expect(SelectedText("hi", appName: "  ")?.appName == nil)
    }

    @Test func longSelectionsAreCutAtTheLimit() throws {
        let selection = try #require(SelectedText(String(repeating: "a", count: SelectedText.limit + 50)))
        #expect(selection.text.count == SelectedText.limit)
        #expect(selection.isShortened)
    }

    @Test func messagePutsTheSelectionBeforeTheQuestion() throws {
        let selection = try #require(SelectedText("E = mc²", appName: "Preview"))
        #expect(SelectedText.message("What does this mean?", about: selection) == """
        <selected_text from="Preview">
        E = mc²
        </selected_text>

        What does this mean?
        """)
        #expect(SelectedText.message("", about: selection) == "<selected_text from=\"Preview\">\nE = mc²\n</selected_text>")
        #expect(SelectedText.message("Plain question", about: nil) == "Plain question")
    }

    @Test func messageWithoutAnAppNamesNone() throws {
        let selection = try #require(SelectedText("text", appName: "My \"Quoted\" App"))
        #expect(SelectedText.message("", about: selection).hasPrefix("<selected_text from=\"My 'Quoted' App\">"))
        let anonymous = try #require(SelectedText("text"))
        #expect(SelectedText.message("", about: anonymous).hasPrefix("<selected_text>\n"))
    }

    @Test func excerptAndQuote() throws {
        let selection = try #require(SelectedText("One  two\n\nthree"))
        #expect(selection.excerpt == "One two three")
        #expect(selection.wordCount == 3)
        #expect(selection.markdownQuote == "> One  two\n>\n> three")
    }
}

@MainActor
struct SelectionInChatTests {
    private func selection(_ text: String = "The mitochondria is the powerhouse of the cell.") -> SelectedText {
        SelectedText(text, appName: "Safari")!
    }

    @Test func sendingAsksAboutTheSelectionAndKeepsItWithTheTurn() async throws {
        let model = ScriptedModel(["It makes energy."])
        let session = GameTestSupport.session(model)
        session.bring(selection())
        session.draft = "Explain"
        session.send()
        await GameTestSupport.settle(session)

        #expect(model.lastMessages == ["<selected_text from=\"Safari\">\nThe mitochondria is the powerhouse of the cell.\n</selected_text>\n\nExplain"])
        #expect(session.draftSelections.isEmpty)
        let turn = try #require(session.turns.first)
        #expect(turn.question == "Explain")
        #expect(turn.selections.map(\.text) == ["The mitochondria is the powerhouse of the cell."])
    }

    @Test func followUpsKeepTheSelectionInTheHistory() async {
        let model = ScriptedModel(["It makes energy.", "Yes."])
        let session = GameTestSupport.session(model)
        session.bring(selection())
        session.draft = "Explain"
        session.send()
        await GameTestSupport.settle(session)
        session.draft = "Really?"
        session.send()
        await GameTestSupport.settle(session)

        #expect(model.lastMessages.first?.hasPrefix("<selected_text from=\"Safari\">") == true)
        #expect(model.lastMessages.last == "Really?")
    }

    @Test func aSelectionAloneCanBeSent() {
        let session = GameTestSupport.session(ScriptedModel(["Sure."]))
        #expect(!session.canSend)
        let text = selection()
        session.bring(text)
        #expect(session.canSend)
        session.removeSelection(text.id)
        #expect(!session.canSend)
    }

    @Test func selectionsAddUpAndTheSameTextComesOnce() {
        let session = GameTestSupport.session(ScriptedModel())
        session.bring(selection("first"))
        session.bring(selection("second"))
        session.bring(selection("first"))
        #expect(session.draftSelections.map(\.text) == ["first", "second"])
    }

    @Test func aFailedQuestionPutsTheSelectionBack() async {
        let session = GameTestSupport.session(ScriptedModel())
        session.bring(selection())
        session.draft = "Explain"
        session.send()
        await GameTestSupport.settle(session)

        #expect(session.turns.isEmpty)
        #expect(session.draft == "Explain")
        #expect(session.draftSelections.map(\.text) == ["The mitochondria is the powerhouse of the cell."])
    }

    @Test func newChatAndGamesLeaveTheSelectionOut() {
        let session = GameTestSupport.session(ScriptedModel())
        session.bring(selection())
        session.reset()
        #expect(session.draftSelections.isEmpty)

        session.startGame(.categories)
        session.bring(selection())
        #expect(session.draftSelections.isEmpty)
    }

    @Test func recentChatsAndMarkdownShowTheSelection() throws {
        var turn = ChatSession.Turn(question: "", images: [], selections: [selection("Bonjour tout le monde")])
        turn.answer = "Hello, everyone."
        let chat = try #require(ChatSession.archiving([turn], into: []).first)
        #expect(chat.title == "Bonjour tout le monde")

        var asked = ChatSession.Turn(question: "Translate", images: [], selections: [selection("Bonjour")])
        asked.answer = "Hello"
        #expect(ChatSession.markdown(for: [asked]) == "**You**\n\n> Bonjour\n\nTranslate\n\n**Assistant**\n\nHello")
    }
}

@MainActor
struct FinderSelectionTests {
    /// A folder with a photo, a text file, and a folder in it, removed when the test ends.
    private final class Selection {
        let root = FileManager.default.temporaryDirectory.appending(path: "MeralineFinderTests-\(UUID().uuidString)")
        var photo: URL { root.appending(path: "photo.png") }
        var notes: URL { root.appending(path: "notes.txt") }
        var project: URL { root.appending(path: "project") }

        init() throws {
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let tiff = try #require(GameTestSupport.image().tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: photo)
            try Data("notes".utf8).write(to: notes)
            try Data("let x = 1".utf8).write(to: project.appending(path: "main.swift"))
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    private func makeSession(agent: Bool = false) -> ChatSession {
        let preferences = GameTestSupport.preferences()
        if agent { preferences.mode = .agent }
        let model = ScriptedModel()
        return ChatSession(preferences: preferences) { model.stream($0) }
    }

    @Test func photosPastTheLimitAreTurnedAway() throws {
        let files = try Selection()
        let session = makeSession()
        for index in 0..<(ImageAttachment.limit + 3) {
            let copy = files.root.appending(path: "photo \(index).png")
            try FileManager.default.copyItem(at: files.photo, to: copy)
            session.attach(fileAt: copy)
        }
        #expect(session.draftImages.count == ImageAttachment.limit)
        #expect(session.draftFiles.isEmpty)
        #expect(session.failure == AttachmentError.limitReached.localizedDescription)
    }

    @Test func anLLMGetsOnlyThePhotos() throws {
        let files = try Selection()
        let session = makeSession()
        session.bring(files: [files.photo, files.notes, files.project])
        #expect(session.draftImages.count == 1)
        #expect(session.draftFiles.isEmpty)
        #expect(session.fileNotice == nil)
    }

    @Test func anAgentGetsFilesAndFolders() throws {
        let files = try Selection()
        let session = makeSession(agent: true)
        session.bring(files: [files.photo, files.notes, files.project])
        #expect(session.draftImages.count == 1)
        #expect(session.draftFiles.map(\.name) == ["notes.txt", "project"])
        #expect(session.draftFiles.map(\.isFolder) == [false, true])
    }

    @Test func aNewSelectionReplacesWhatTheLastOneBroughtButNotWhatYouAttached() throws {
        let files = try Selection()
        let session = makeSession(agent: true)
        session.attach(fileAt: files.notes)
        session.bring(files: [files.project])
        session.bring(files: [files.project])
        #expect(session.draftFiles.map(\.name) == ["notes.txt", "project"])
        session.bring(files: [files.photo])
        #expect(session.draftFiles.map(\.name) == ["notes.txt"])
        #expect(session.draftImages.count == 1)
    }

    @Test func aSelectionAnLLMCantReadTakesTheEarlierPhotosAway() throws {
        let files = try Selection()
        let session = makeSession()
        session.bring(files: [files.photo])
        session.bring(files: [files.notes])
        #expect(session.draftImages.isEmpty)
        #expect(session.draftFiles.isEmpty)
    }

    @Test func nothingSelectedNowTakesAnEarlierSelectionAway() throws {
        let files = try Selection()
        let session = makeSession(agent: true)
        session.draft = "Typed"
        session.attach(fileAt: files.notes)
        session.bringCurrentSelection(text: SelectedText("old quote"), files: [])
        #expect(session.offeredSelection?.text == "old quote")
        #expect(session.draftSelections.isEmpty)

        session.bringCurrentSelection(text: nil, files: [files.project])
        #expect(session.offeredSelection == nil)
        #expect(session.draftFiles.map(\.name) == ["notes.txt", "project"])

        session.bringCurrentSelection(text: nil, files: [])
        #expect(session.offeredSelection == nil)
        #expect(session.draftFiles.map(\.name) == ["notes.txt"])
        #expect(session.draft == "Typed")
    }

    @Test func theServicesMenuBringsEverythingLikeADrop() throws {
        let files = try Selection()
        let session = makeSession()
        session.bring(files: [files.notes], deliberately: true)
        #expect(session.draftFiles.map(\.name) == ["notes.txt"])
        #expect(session.fileNotice != nil)
    }

    @Test func gamesTakeNoFiles() throws {
        let files = try Selection()
        let session = makeSession()
        session.startGame(.categories)
        session.bring(files: [files.photo])
        #expect(session.draftImages.isEmpty)
    }

    @Test func backspaceTakesOutTheSelectionThenTheLastAttachment() throws {
        let files = try Selection()
        let session = makeSession(agent: true)
        session.bring(files: [files.photo, files.notes])
        session.bring(SelectedText("quote")!)
        #expect(session.removeLastContext())
        #expect(session.draftSelections.isEmpty)
        #expect(session.removeLastContext())
        #expect(session.draftFiles.isEmpty)
        #expect(session.removeLastContext())
        #expect(session.draftImages.isEmpty)
        #expect(!session.removeLastContext())
    }
}

@MainActor
struct CopiedSelectionTests {
    /// A pasteboard of the test's own, holding `text` and, beside it, `data` under `type`, written the way
    /// Zed and Chromium write theirs: types that aren't UTIs only go through `setData(_:forType:)`.
    private func pasteboard(_ text: String = "let x = 1\n", type: String? = nil, data: Data? = nil) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MeralineTests.\(UUID().uuidString)"))
        let custom = type.map(NSPasteboard.PasteboardType.init(rawValue:))
        pasteboard.declareTypes([.string] + (custom.map { [$0] } ?? []), owner: nil)
        pasteboard.setString(text, forType: .string)
        if let custom, let data { pasteboard.setData(data, forType: custom) }
        return pasteboard
    }

    private func pasteboard(type: String, json: String) -> NSPasteboard {
        pasteboard(type: type, data: Data(json.utf8))
    }

    @Test func zedsLineCopyIsNoSelection() {
        let line = #"[{"len":10,"is_entire_line":true,"first_line_indent":0,"file_path":null,"line_range":null}]"#
        #expect(SelectionReader.isCopyOfEmptySelection(pasteboard(type: "zed-metadata", json: line)))
    }

    @Test func aRealSelectionInZedCounts() {
        let selected = #"[{"len":5,"is_entire_line":false,"first_line_indent":0}]"#
        #expect(!SelectionReader.isCopyOfEmptySelection(pasteboard(type: "zed-metadata", json: selected)))
        let mixed = #"[{"len":5,"is_entire_line":true},{"len":3,"is_entire_line":false}]"#
        #expect(!SelectionReader.isCopyOfEmptySelection(pasteboard(type: "zed-metadata", json: mixed)))
    }

    @Test func vsCodesLineCopyIsNoSelection() {
        #expect(SelectionReader.isCopyOfEmptySelection(pasteboard(type: "vscode-editor-data", json: #"{"version":1,"isFromEmptySelection":true}"#)))
        #expect(!SelectionReader.isCopyOfEmptySelection(pasteboard(type: "vscode-editor-data", json: #"{"version":1,"isFromEmptySelection":false}"#)))
    }

    @Test func vsCodesLineCopyInsideChromiumsBundleIsNoSelection() throws {
        // Chromium's bundle: a count, then each format's name and data as UTF-16 strings.
        var bundle = Data([2, 0, 0, 0])
        bundle += try #require("vscode-editor-data".data(using: .utf16LittleEndian))
        bundle += try #require(#"{"version":1,"isFromEmptySelection":true,"mode":"swift"}"#.data(using: .utf16LittleEndian))
        #expect(SelectionReader.isCopyOfEmptySelection(pasteboard(type: "org.chromium.web-custom-data", data: bundle)))
        let selected = try #require(#"{"version":1,"isFromEmptySelection":false}"#.data(using: .utf16LittleEndian))
        #expect(!SelectionReader.isCopyOfEmptySelection(pasteboard(type: "org.chromium.web-custom-data", data: selected)))
    }

    @Test func plainTextCounts() {
        #expect(!SelectionReader.isCopyOfEmptySelection(pasteboard()))
    }

    @Test func theLayoutHasAKeyForC() {
        #expect(SelectionReader.keyCode(typing: "c") != nil)
    }
}
