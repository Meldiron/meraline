import AppKit
import Foundation
import Testing
@testable import Meraline

struct RhymeDuelRulesTests {
    @Test func theLastWordIsWhatHasToRhyme() {
        #expect(RhymeDuel.rhymeWord(of: "I went out walking in the rain,") == "rain")
        #expect(RhymeDuel.rhymeWord(of: "Don't stop!!!") == "stop")
        #expect(RhymeDuel.rhymeWord(of: "It's over now, isn't it?") == "it")
        #expect(RhymeDuel.rhymeWord(of: "… 42 —") == nil)
    }

    @Test func commonRhymesPassByEar() {
        let pairs = [
            ("rain", "again"), ("rain", "plane"), ("rain", "brain"), ("day", "way"), ("moon", "June"),
            ("light", "kite"), ("light", "night"), ("love", "dove"), ("cat", "hat"), ("blue", "true"),
            ("free", "sea"), ("sky", "fly"), ("go", "snow"), ("heart", "art"), ("time", "rhyme"),
            ("her", "fur"), ("walking", "talking"), ("style", "mile"), ("Rain", "PLANE")
        ]
        for (word, other) in pairs {
            #expect(RhymeDuel.rhymes(word, with: other), "\(word) should rhyme with \(other)")
            #expect(RhymeDuel.rhymes(other, with: word), "\(other) should rhyme with \(word)")
        }
    }

    @Test func nonRhymesAndTheSameWordAreRefused() {
        let pairs = [("rain", "sun"), ("day", "night"), ("cat", "dog"), ("light", "dark"), ("rain", "rain"), ("", "rain")]
        for (word, other) in pairs {
            #expect(!RhymeDuel.rhymes(word, with: other), "\(word) should not rhyme with \(other)")
        }
    }

    @Test func aComplaintNamesBothWords() throws {
        let opening = "I went out walking in the rain"
        let complaint = try #require(RhymeDuel.complaint(about: "And then I saw the sun", after: opening))
        #expect(complaint.contains("“sun”"))
        #expect(complaint.contains("“rain”"))
        #expect(RhymeDuel.complaint(about: "It fell like tears upon the plane", after: opening) == nil)
        #expect(RhymeDuel.complaint(about: opening, after: opening)?.contains("again") == true)
        #expect(RhymeDuel.complaint(about: "…", after: opening)?.contains("“rain”") == true)
        #expect(RhymeDuel.complaint(about: "Anything goes", after: "1, 2, 3") == nil, "nothing to rhyme with lets the line through")
    }

    @Test func onlyTheFirstLineCounts() {
        #expect(RhymeDuel.line(from: "\n  first line  \nsecond line") == "first line")
        #expect(RhymeDuel.line(from: "   ") == "")
    }

    @Test func modelAnswersAreCleanedUp() {
        #expect(RhymeDuel.cleanedAnswer("“It fell like tears upon the plane.”\n\nWant another?") == "It fell like tears upon the plane.")
        #expect(RhymeDuel.cleanedAnswer("PASS") == "")
        #expect(RhymeDuel.cleanedAnswer(" *pass.* ") == "")
        #expect(RhymeDuel.cleanedAnswer("Pass the salt, the soup is bland") == "Pass the salt, the soup is bland")
    }

    @Test func statusCountsLinesAndEnds() {
        #expect(RhymeDuel.status(linesPlayed: 0) == "Line 1 of 8")
        #expect(RhymeDuel.status(linesPlayed: 7) == "Line 8 of 8")
        #expect(RhymeDuel.status(linesPlayed: 8) == "Duel done")
    }

    @Test func thePromptHasTheModelOpenWithOneLineOrPass() {
        #expect(RhymeDuel.systemPrompt.contains("you go first"))
        #expect(RhymeDuel.systemPrompt.contains("one line"))
        #expect(RhymeDuel.systemPrompt.contains(RhymeDuel.pass))
        #expect(!RhymeDuel.opening.isEmpty)
        #expect(RhymeDuel.passed(on: nil).contains("open"))
        #expect(RhymeDuel.passed(on: "rain").contains("“rain”"))
    }
}

@MainActor
struct RhymeDuelSessionTests {
    private typealias Support = GameTestSupport

    private let opening = "I went out walking in the rain"
    private let exchanges = [
        ("It fell like tears upon the plane", "And soaked the fields of golden grain"),
        ("It hit me later like a train", "I said it once, I’ll say again"),
        ("The puddles gathered in the lane", "And washed the worries from my brain")
    ]
    private let closing = "So here I am, out in the rain"

    /// A duel as it is remembered: the model's opening line, the exchanges after it (your line, then the
    /// model's), and your closing line, which gets no reply.
    private func duel(exchanges: [(String, String)] = [], closing: String? = nil) -> ChatSession.PastChat {
        var turns = [Support.turn(cue: RhymeDuel.opening, reply: opening)]
        turns += exchanges.map { Support.turn($0.0, reply: $0.1) }
        if let closing { turns.append(Support.turn(closing)) }
        return ChatSession.PastChat(turns: turns, date: .now, mode: .game(.rhymeDuel))
    }

    @Test func startingADuelAsksTheModelToOpen() async {
        let model = ScriptedModel([opening])
        let session = Support.session(model)
        session.draft = "half a question"
        session.startGame(.rhymeDuel)
        #expect(session.game == .rhymeDuel)
        #expect(session.draft.isEmpty)
        #expect(session.isStreaming, "the model goes first")
        #expect(session.turns.first?.cue == RhymeDuel.opening)
        #expect(session.nudge == RhymeDuel.invitation)
        #expect(model.requests.first?.systemPrompt == RhymeDuel.systemPrompt)
        #expect(model.lastMessages == [RhymeDuel.opening])
        await Support.settle(session)
        #expect(session.isYourMove)
        #expect(session.gameState?.status == "Line 2 of 8")
        #expect(RhymeDuel.lines(for: session.turns).map(\.text) == [opening])
        session.reset()
        #expect(session.game == nil)
        #expect(session.history.first?.title == "Rhyme Duel: \(opening)")
    }

    @Test func withoutAProviderTheOpeningWaitsForSettings() {
        let session = Support.session(ScriptedModel(), withProvider: false)
        session.startGame(.rhymeDuel)
        #expect(session.game == .rhymeDuel)
        #expect(session.turns.isEmpty)
        #expect(session.failureNeedsSettings)
        #expect(session.canSend, "Return asks the model to open again")
        #expect(!session.isYourMove)
    }

    @Test func aMissedRhymeComesBackInsteadOfAskingTheModel() {
        let model = ScriptedModel()
        let session = Support.session(model)
        session.reopen(duel())
        #expect(session.isYourMove)
        #expect(session.gameState?.phase == .yourMove(placeholder: "Rhyme with “rain”…"))
        session.draft = "And then I saw the sun"
        session.send()
        #expect(model.requests.isEmpty)
        #expect(session.turns.count == 1)
        #expect(session.draft == "And then I saw the sun", "the line waits in the input to be fixed")
        #expect(session.nudge?.contains("“sun”") == true)
        #expect(session.failure == nil)
    }

    @Test func sendingTheSameLineAgainInsists() {
        let model = ScriptedModel()
        let session = Support.session(model)
        session.reopen(duel())
        session.draft = "And then I saw the sun"
        session.send()
        #expect(model.requests.isEmpty)
        session.send()
        #expect(model.requests.count == 1, "the second try goes to the model")
        #expect(session.isStreaming)
    }

    @Test func theModelsLineIsCleanedUp() async {
        let model = ScriptedModel(["“And soaked the fields of golden grain.”\n\nWant another?"])
        let session = Support.session(model)
        session.reopen(duel())
        await Support.play(exchanges[0].0, in: session)
        #expect(session.turns.last?.answer == "And soaked the fields of golden grain.")
        #expect(model.requests.first?.messages.map(\.role) == [.user, .assistant, .user])
        #expect(model.lastMessages == [RhymeDuel.opening, opening, exchanges[0].0])
    }

    @Test func aPassSendsTheLineBack() async {
        let model = ScriptedModel(["PASS"])
        let session = Support.session(model)
        session.reopen(duel())
        await Support.play(exchanges[0].0, in: session)
        #expect(session.turns.count == 1, "the pass did not cost a turn")
        #expect(session.draft == exchanges[0].0)
        #expect(session.nudge == RhymeDuel.passed(on: "plane"))
    }

    @Test func theLastWordIsYoursAndReturnStartsARematch() {
        let model = ScriptedModel()
        let session = Support.session(model)
        session.reopen(duel(exchanges: exchanges))
        #expect(session.gameState?.status == "Line 8 of 8")
        session.draft = closing
        session.send()
        #expect(model.requests.isEmpty, "the closing line is not sent anywhere")
        #expect(session.failure == nil)
        #expect(session.turns.count == 5)
        #expect(session.gameState?.status == "Duel done")
        #expect(session.nudge == RhymeDuel.done)
        let poem = [opening] + exchanges.flatMap { [$0.0, $0.1] } + [closing]
        #expect(session.conversationMarkdown == poem.joined(separator: "\n"))

        session.send()
        #expect(model.requests.count == 1, "Return asks for a rematch")
        #expect(session.turns.last?.cue == RhymeDuel.rematchCue)
        #expect(model.requests.last?.messages.last?.text == "\(closing)\n\n\(RhymeDuel.rematchCue)", "two user messages in a row are joined")
    }

    @Test func imagesSitTheDuelOut() {
        let session = Support.session(ScriptedModel())
        session.reopen(duel())
        session.attach(Support.image())
        #expect(session.draftImages.isEmpty)
        #expect(session.nudge == Game.noImages)
        #expect(session.failure == nil)
    }

    @Test func aDuelIsRememberedAsOne() throws {
        let session = Support.session(ScriptedModel())
        session.reopen(duel(exchanges: exchanges, closing: closing))
        #expect(session.nudge == RhymeDuel.done)
        session.reset()
        let remembered = try #require(session.history.first)
        #expect(remembered.mode == .game(.rhymeDuel))
        #expect(remembered.title == "Rhyme Duel: \(opening)")
        #expect(remembered.turns.count == 5, "the closing line, which has no reply, is kept")
        session.reopen(remembered.id)
        #expect(session.game == .rhymeDuel)
        #expect(session.history.isEmpty)
    }

    @Test func expiringEndsTheDuel() {
        let session = Support.session(ScriptedModel())
        session.reopen(duel())
        session.expire()
        #expect(session.game == nil)
        #expect(session.turns.isEmpty)
        #expect(session.nudge == nil)
        #expect(session.history.first?.mode == .game(.rhymeDuel))
    }
}
