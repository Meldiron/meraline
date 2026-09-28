import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import Meraline

struct NoteStackTests {
    /// A pile of `answers`, torn off in that order, so the last is on top.
    private func pile(_ answers: String...) -> NoteStack {
        var stack = NoteStack()
        for answer in answers { stack.add(answer: answer, question: "Q \(answer)") }
        return stack
    }

    @Test func theAnswerTornOffLastIsOnTop() {
        let stack = pile("a", "b", "c")
        #expect(stack.count == 3)
        #expect(stack.front?.answer == "c")
        #expect(stack.front?.question == "Q c")
        #expect(stack.position == 1)
        #expect(stack.badge == "1/3")
        #expect(stack.peeking.map(\.answer) == ["b", "a"])
    }

    @Test func aSingleNoteHasNoBadgeAndNothingBehindIt() {
        let stack = pile("a")
        #expect(stack.badge == nil)
        #expect(stack.peeking.isEmpty)
        #expect(NoteStack().front == nil)
    }

    @Test func theBadgeFlipsThroughThePileAndRoundAgain() {
        var stack = pile("a", "b", "c")
        stack.take(.next)
        #expect(stack.front?.answer == "b")
        #expect(stack.badge == "2/3")
        #expect(stack.peeking.map(\.answer) == ["a", "c"])
        stack.take(.next)
        stack.take(.next)
        #expect(stack.front?.answer == "c")
        stack.take(.previous)
        #expect(stack.front?.answer == "a")
        #expect(stack.badge == "3/3")
    }

    @Test func atMostTwoNotesPeekOut() {
        let stack = pile("a", "b", "c", "d", "e")
        #expect(stack.peeking.map(\.answer) == ["d", "c"])
    }

    @Test func anAnswerAlreadyInThePileComesForwardInsteadOfACopy() {
        var stack = pile("a", "b", "c")
        stack.add(answer: "a", question: "Q a")
        #expect(stack.count == 3)
        #expect(stack.front?.answer == "a")
        // The same answer to another question is a note of its own.
        stack.add(answer: "a", question: "Something else")
        #expect(stack.count == 4)
        #expect(stack.position == 1)
    }

    @Test func closingTheFrontNoteBringsTheOneBehindIt() {
        var stack = pile("a", "b", "c")
        stack.take(.next)
        stack.removeFront()
        #expect(stack.front?.answer == "a")
        #expect(stack.badge == "2/2")
        // Past the bottom of the pile, the top comes forward.
        stack.removeFront()
        #expect(stack.front?.answer == "c")
        #expect(stack.badge == nil)
        stack.removeFront()
        #expect(stack.isEmpty)
        #expect(stack.front == nil)
    }

    @Test func tabKeysStepThroughThePile() {
        #expect(NoteStack.Step(keyCode: UInt16(kVK_Tab), characters: "\t", modifiers: .control) == .next)
        #expect(NoteStack.Step(keyCode: UInt16(kVK_Tab), characters: "\t", modifiers: [.control, .shift]) == .previous)
        #expect(NoteStack.Step(keyCode: UInt16(kVK_ANSI_RightBracket), characters: "}", modifiers: [.command, .shift]) == .next)
        #expect(NoteStack.Step(keyCode: UInt16(kVK_ANSI_LeftBracket), characters: "{", modifiers: [.command, .shift]) == .previous)
        // Tab alone moves between the note's buttons, and ⌘] is no step.
        #expect(NoteStack.Step(keyCode: UInt16(kVK_Tab), characters: "\t", modifiers: []) == nil)
        #expect(NoteStack.Step(keyCode: UInt16(kVK_ANSI_RightBracket), characters: "]", modifiers: .command) == nil)
    }

    @Test func theNotesBehindPeekOutUnderTheFrontCard() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 214)
        let peek = NoteStackGeometry.peek
        let front = NoteStackGeometry.card(0, in: rect, depth: 2).boundingRect
        #expect(abs(front.height - (214 - 2 * peek)) < 0.01)
        let behind = NoteStackGeometry.card(1, in: rect, depth: 2).boundingRect
        #expect(abs(behind.maxY - (front.maxY + peek)) < 0.01)
        #expect(abs(behind.width - (300 - 2 * NoteStackGeometry.inset)) < 0.01)
        // Only its bottom edge shows: nothing of it inside the front card.
        let edge = NoteStackGeometry.edge(1, in: rect, depth: 2)
        #expect(!edge.contains(CGPoint(x: 150, y: front.midY)))
        #expect(edge.contains(CGPoint(x: 150, y: front.maxY + peek / 2)))
        #expect(!NoteStackGeometry.edge(2, in: rect, depth: 2).contains(CGPoint(x: 150, y: front.maxY + peek / 2)))
        #expect(NoteStackGeometry.edge(2, in: rect, depth: 2).contains(CGPoint(x: 150, y: front.maxY + peek * 1.5)))
        #expect(abs(NoteStackGeometry.outline(in: rect, depth: 2).boundingRect.maxY - rect.maxY) < 0.01)
    }

    @Test func aNoteDeeperThanThePileHidesUnderTheLastThatShows() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 207)
        // At most a hairline where the edges meet, and the edge fades out there anyway.
        #expect(NoteStackGeometry.edge(2, in: rect, depth: 1).boundingRect.height < 1)
        #expect(NoteStackGeometry.edge(1, in: rect, depth: 0).boundingRect.height < 1)
    }
}

/// The note itself: answers torn off while it is open go onto its pile in the one window, and its keys and cross
/// work through the pile. Its window opens far off every screen, so the test run shows nothing.
@MainActor
struct TornOffPileTests {
    private func tearOff(_ answer: String, into notes: AnswerNotes) {
        notes.open(answer: answer, question: "Q \(answer)", at: NSPoint(x: -20_000, y: -20_000))
    }

    private func press(_ characters: String, _ modifiers: NSEvent.ModifierFlags, keyCode: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
        )!
    }

    /// Long enough for the answer in front to fade out and the next to come forward.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(250))
    }

    @Test func answersTornOffWhileTheNoteIsOpenPileUpInOneWindow() async throws {
        let notes = AnswerNotes()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        tearOff("a", into: notes)
        tearOff("b", into: notes)
        tearOff("c", into: notes)
        tearOff("b", into: notes)
        await settle()
        let windows = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) }
        #expect(windows.count == 1)
        #expect(notes.stack.count == 3)
        #expect(notes.stack.front?.answer == "b", "an answer already in the pile comes forward")
        notes.closeAll()
        #expect(notes.stack.isEmpty)
        #expect(windows.allSatisfy { !$0.isVisible })
    }

    @Test func eachAnswerOnThePileKeepsItsOwnChatsWorkspace() async throws {
        let notes = AnswerNotes()
        let agents = URL(filePath: "/tmp/agent-chat", directoryHint: .isDirectory)
        notes.open(answer: "See out/report.md", question: "Write a report", workspace: agents, at: NSPoint(x: -20_000, y: -20_000))
        notes.open(answer: "356 °F", question: "180 °C in Fahrenheit?", at: NSPoint(x: -20_000, y: -20_000))
        await settle()
        #expect(notes.stack.front?.workspace == nil, "an LLM's answer has no workspace")
        #expect(notes.stack.peeking.first?.workspace == agents, "the agent's answer behind it keeps its own")
        notes.closeAll()
    }

    @Test func keysFlipThroughThePileAndTheCrossPutsAwayTheNoteInFront() async throws {
        let notes = AnswerNotes()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        for answer in ["a", "b", "c"] { tearOff(answer, into: notes) }
        await settle()
        let window = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) })

        window.sendEvent(press("\t", .control, keyCode: kVK_Tab))
        await settle()
        #expect(notes.stack.front?.answer == "b")
        window.sendEvent(press("{", [.command, .shift], keyCode: kVK_ANSI_LeftBracket))
        await settle()
        #expect(notes.stack.front?.answer == "c")

        // ⌘W, like Esc and the cross, puts away only the note in front, and the last takes the window with it.
        window.performClose(nil)
        await settle()
        #expect(notes.stack.count == 2)
        #expect(notes.stack.front?.answer == "b")
        #expect(window.isVisible)
        window.performClose(nil)
        await settle()
        window.performClose(nil)
        await settle()
        #expect(notes.stack.isEmpty)
        #expect(!window.isVisible)
    }
}
