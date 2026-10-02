import Foundation
import SwiftUI
import Testing
@testable import Meraline

/// Show What Changed: an answer that put right the text its question was about knows what it changed, and the
/// chat's actions swap it for the changes and back.
@MainActor
struct ShowWhatChangedTests {
    private typealias Support = GameTestSupport

    private func fixGrammar(replying replies: [String], text: SelectedText? = SelectedText("i has a apple", appName: "Notes")) async throws -> ChatSession {
        let session = Support.session(ScriptedModel(replies))
        session.bring(try #require(text))
        await play("Fix the grammar", in: session)
        return session
    }

    /// Asks, then waits for the answer and for what it changed, which is worked out off the main actor.
    private func play(_ line: String, in session: ChatSession) async {
        await Support.play(line, in: session)
        await session.changesSearch?.value
    }

    @Test func anAnswerThatPutsTheSelectedTextRightKnowsWhatItChanged() async throws {
        let session = try await fixGrammar(replying: ["I have an apple."])
        let changes = try #require(session.turns.first?.changes)
        #expect(changes.count == 4)
        #expect(changes.segments.contains(.removed("has")))
        #expect(changes.segments.contains(.added("have")))
    }

    @Test func copiedTextToo() async throws {
        let session = try await fixGrammar(replying: ["I have an apple."], text: SelectedText.clipboard("i has a apple"))
        #expect(session.turns.first?.changes?.count == 4)
    }

    @Test func anAnswerAboutTheTextHasNone() async throws {
        let session = try await fixGrammar(replying: ["It says someone owns an apple."])
        #expect(session.turns.first?.changes == nil)
    }

    @Test func aQuestionAboutNoTextHasNone() async {
        let session = Support.session(ScriptedModel(["I have an apple."]))
        await play("i has a apple", in: session)
        #expect(session.turns.first?.changes == nil, "what is typed is the question, not a text to change")
    }

    @Test func aFollowUpIsComparedWithTheTextAskedAboutBefore() async throws {
        let session = try await fixGrammar(replying: ["I have an apple.", "i have a apple."])
        await play("Keep the lowercase i and the “a”", in: session)
        let changes = try #require(session.turns.last?.changes)
        #expect(changes.segments == [.same("i "), .removed("has"), .added("have"), .same(" a apple"), .added(".")])
    }

    @Test func askAgainLooksAgain() async throws {
        let session = try await fixGrammar(replying: ["I have an apple.", "i have a apple."])
        let first = try #require(session.turns.first?.changes)
        session.askAgain()
        await Support.settle(session)
        await session.changesSearch?.value
        let again = try #require(session.turns.first?.changes)
        #expect(first.count == 4)
        #expect(again.count == 2)
    }

    @Test func aStoppedAnswerHasNone() async throws {
        let session = ChatSession(preferences: Support.preferences(), usage: UsageLedger(file: nil)) { _ in
            AsyncThrowingStream { $0.yield(.text("I have an apple.")) }
        }
        session.bring(try #require(SelectedText("i has a apple")))
        session.draft = "Fix the grammar"
        session.send()
        for _ in 0..<100 where session.turns.last?.answer.isEmpty != false { await Task.yield() }
        session.stop()
        await Support.settle(session)
        #expect(session.turns.first?.answer == "I have an apple.")
        #expect(session.turns.first?.changes == nil)
    }

    @Test func aTurnThatWentMeanwhileIsLeftBe() async throws {
        let session = Support.session(ScriptedModel(["I have an apple."]))
        session.bring(try #require(SelectedText("i has a apple")))
        await Support.play("Fix the grammar", in: session)
        session.deleteChat()
        await session.changesSearch?.value
        #expect(session.turns.isEmpty)
    }

    @Test func recentChatsKeepThem() async throws {
        let session = try await fixGrammar(replying: ["I have an apple."])
        session.reset()
        let chat = try #require(session.history.first)
        session.reopen(chat.id)
        #expect(session.turns.first?.changes?.count == 4)
    }

    @Test func commandDShowsTheChangesAndTheAnswerAgain() async throws {
        let session = try await fixGrammar(replying: ["I have an apple."])
        let layout = PanelLayout()
        let context = PanelContext(session: session, preferences: Support.preferences(), layout: layout, openSettings: { _ in })
        let show = try #require(context.action(forKeyCode: 0, characters: "d", modifiers: .command))
        #expect(show.id == "showChanges")
        #expect(show.title == "Show What Changed")
        #expect(show.subtitle == "30% changed · 4 edits")
        #expect(context.chatMenu?.sections.map(\.id).prefix(2) == ["primary", "changes"])
        context.run(show, in: .chat, fromShortcut: true)
        #expect(layout.answersShowingChanges == [session.turns[0].id])

        let back = try #require(context.chatMenu?.actions.first { $0.id == "showChanges" })
        #expect(back.title == "Show Answer")
        context.run(back, in: .chat)
        #expect(layout.answersShowingChanges.isEmpty)
    }

    @Test func theTextThatStayedIsGrayAndWhatChangedSitsOnATint() throws {
        let changes = try #require(TextChanges.diff(from: "i has a apple", to: "i have a apple"))
        let text = ChangesView.text(of: changes, fontSize: 15)
        let runs = text.runs.map { (String(text[$0.range].characters), $0) }
        let stayed = try #require(runs.first { $0.0 == " a apple" }?.1)
        #expect(stayed.foregroundColor == .secondary, "what stayed is context for checking the changes")
        #expect(stayed.backgroundColor == nil)
        let went = try #require(runs.first { $0.0 == "has" }?.1)
        #expect(went.strikethroughStyle != nil)
        #expect(went.backgroundColor == Color(nsColor: .removedTint))
        let came = try #require(runs.first { $0.0 == "have" }?.1)
        #expect(came.strikethroughStyle == nil)
        #expect(came.backgroundColor == Color(nsColor: .addedTint))
        #expect(came.foregroundColor == Color(nsColor: .addedText))
    }

    @Test func noChangesNoAction() async throws {
        let session = try await fixGrammar(replying: ["It says someone owns an apple."])
        let context = PanelContext(session: session, preferences: Support.preferences(), layout: PanelLayout(), openSettings: { _ in })
        #expect(context.chatMenu?.actions.contains { $0.id == "showChanges" } == false)
        #expect(context.action(forKeyCode: 0, characters: "d", modifiers: .command) == nil)
    }

    @Test func whileAFollowUpIsAnsweredTheActionWaits() async throws {
        var calls = 0
        let session = ChatSession(preferences: Support.preferences(), usage: UsageLedger(file: nil)) { _ in
            calls += 1
            let call = calls
            return AsyncThrowingStream { continuation in
                continuation.yield(.text(call == 1 ? "I have an apple." : "Sure"))
                if call == 1 { continuation.finish() }
            }
        }
        session.bring(try #require(SelectedText("i has a apple")))
        await play("Fix the grammar", in: session)
        #expect(session.turns.first?.changes != nil)
        session.draft = "Thanks"
        session.send()
        let context = PanelContext(session: session, preferences: Support.preferences(), layout: PanelLayout(), openSettings: { _ in })
        #expect(session.isStreaming)
        #expect(context.chatMenu?.actions.contains { $0.id == "showChanges" } == false)
        session.stop()
        await Support.settle(session)
    }
}
