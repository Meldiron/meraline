import AppKit
import SwiftUI
import Testing
@testable import Meraline

@MainActor
struct OneLineInputTests {
    @Test func showsLineBreaksAsMarks() {
        #expect("def f(x):\n    return x\r\nprint(f(3))".onOneLine == "def f(x):⏎    return x⏎print(f(3))")
    }

    @Test func marksComeBackAsLineBreaks() {
        #expect("one⏎two⏎⏎three".withLineBreaks == "one\ntwo\n\nthree")
    }

    @Test func textWithoutLineBreaksStaysAsItIs() {
        let question = "How many digits 8 are there in all numbers from 1 to 1 billion?"
        #expect(question.onOneLine == question)
        #expect(question.withLineBreaks == question)
        #expect("".onOneLine.isEmpty)
    }

    @Test func bindingKeepsTheDraftsLineBreaks() {
        var draft = "first\nsecond"
        let field = Binding(get: { draft }, set: { draft = $0 }).onOneLine
        #expect(field.wrappedValue == "first⏎second")
        field.wrappedValue = "first⏎second⏎third"
        #expect(draft == "first\nsecond\nthird")
        field.wrappedValue = "pasted\nstraight in"
        #expect(draft == "pasted\nstraight in")
    }

    @Test func pastesLineBreaksAsMarksAtTheCaret() {
        let pasteboard = NSPasteboard(name: .init("OneLineInputTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("A\nB", forType: .string)

        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.string = "hello world"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(editor.pasteOnOneLine(from: pasteboard))
        #expect(editor.string == "helloA⏎B world")

        pasteboard.clearContents()
        pasteboard.setString("no breaks", forType: .string)
        #expect(!editor.pasteOnOneLine(from: pasteboard))
    }
}
