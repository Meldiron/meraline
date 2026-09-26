import Foundation
import Testing
@testable import Meraline

@MainActor
struct HistoryTests {
    private func turn(_ question: String, _ answer: String) -> ChatSession.Turn {
        var turn = ChatSession.Turn(question: question, images: [])
        turn.answer = answer
        return turn
    }

    @Test func newestChatComesFirst() {
        var history = ChatSession.archiving([turn("First?", "One")], into: [])
        history = ChatSession.archiving([turn("Second?", "Two")], into: history)
        #expect(history.map(\.title) == ["Second?", "First?"])
    }

    @Test func keepsOnlyTheLastFiveChats() {
        var history: [ChatSession.PastChat] = []
        for index in 1...7 {
            history = ChatSession.archiving([turn("Question \(index)", "Answer")], into: history)
        }
        #expect(history.count == ChatSession.historyLimit)
        #expect(history.first?.title == "Question 7")
        #expect(history.last?.title == "Question 3")
    }

    @Test func skipsChatsWithoutAnswers() {
        let history = ChatSession.archiving([turn("Unanswered", "")], into: [])
        #expect(history.isEmpty)
    }

    @Test func archivedTurnsAreComplete() throws {
        var streaming = turn("Partial?", "Half an ans")
        streaming.activity = .thinking
        let chat = try #require(ChatSession.archiving([streaming], into: []).first)
        #expect(chat.turns.first?.isComplete == true)
        #expect(chat.turns.first?.activity == nil)
    }

    @Test func resettingAnEmptyChatAddsNothing() {
        let session = ChatSession(preferences: Preferences(
            defaults: UserDefaults(suiteName: "MeralineTests.\(UUID().uuidString)")!,
            secrets: SecretStore(read: { _ in "" }, write: { _, _ in }),
            onDeviceModelAvailable: false
        ))
        #expect(session.history.isEmpty)
        session.reset()
        #expect(session.history.isEmpty)
    }

    @Test func forgettingEmptiesTheRecentChats() async {
        let model = ScriptedModel(["One", "Two"])
        let session = GameTestSupport.session(model)
        await GameTestSupport.play("First?", in: session)
        session.reset()
        await GameTestSupport.play("Second?", in: session)
        session.reset()
        #expect(session.history.count == 2)
        #expect(session.forgetHistory() == 2)
        #expect(session.history.isEmpty)
        #expect(session.forgetHistory() == 0)
    }

    @Test func conversationMarkdownListsEveryAnsweredTurn() throws {
        var withImage = turn("", "A cat.")
        withImage = ChatSession.Turn(question: "", images: [ImageAttachment(mediaType: "image/png", data: Data([1]))])
        withImage.answer = "A cat."
        let markdown = try #require(ChatSession.markdown(for: [
            turn("Capital of France?", "Paris.\n"),
            turn("Unanswered", ""),
            withImage
        ]))
        #expect(markdown == """
        **You**

        Capital of France?

        **Assistant**

        Paris.

        ---

        **You**

        _1 image attached_

        **Assistant**

        A cat.
        """)
        #expect(ChatSession.markdown(for: [turn("Nothing yet", "")]) == nil)
    }
}
