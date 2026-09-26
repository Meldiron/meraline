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
        let opening = RhymeDuel.Verse(line: "I went out walking in the rain")
        let complaint = try #require(RhymeDuel.complaint(about: "And then I saw the sun", after: opening))
        #expect(complaint.contains("“sun”"))
        #expect(complaint.contains("“rain”"))
        #expect(RhymeDuel.complaint(about: "It fell like tears upon the plane", after: opening) == nil)
        #expect(RhymeDuel.complaint(about: opening.line, after: opening)?.contains("again") == true)
        #expect(RhymeDuel.complaint(about: "…", after: opening)?.contains("“rain”") == true)
        #expect(RhymeDuel.complaint(about: "Anything goes", after: .init(line: "1, 2, 3")) == nil, "nothing to rhyme with lets the line through")
    }

    @Test func aRhymeTheModelGaveCountsWhateverTheEarSays() {
        #expect(!RhymeDuel.rhymes("more", with: "door"), "spelling alone misses this one")
        let bare = RhymeDuel.Verse(line: "A cat sat waiting by the door")
        let hinted = RhymeDuel.Verse(line: bare.line, rhymes: ["floor", "more"])
        #expect(RhymeDuel.complaint(about: "She wanted nothing more", after: bare) != nil)
        #expect(RhymeDuel.complaint(about: "She wanted nothing More!", after: hinted) == nil)
        #expect(RhymeDuel.complaint(about: "Until the clouds began to pour", after: bare) != nil)
        #expect(RhymeDuel.complaint(about: "Until the clouds began to pour", after: .init(line: bare.line, rhymes: ["four"])) == nil, "by way of “four”")
        #expect(RhymeDuel.complaint(about: "And then I saw the sun", after: hinted)?.contains("“door”") == true)
    }

    @Test func onlyTheFirstLineCounts() {
        #expect(RhymeDuel.line(from: "\n  first line  \nsecond line") == "first line")
        #expect(RhymeDuel.line(from: "   ") == "")
    }

    @Test func modelAnswersAreCleanedUp() {
        #expect(RhymeDuel.verse(from: "“It fell like tears upon the plane.”\n\nWant another?") == .init(line: "It fell like tears upon the plane."))
        #expect(RhymeDuel.verse(from: "Pass the salt, the soup is bland") == .init(line: "Pass the salt, the soup is bland"))
        #expect(RhymeDuel.verse(from: " | floor, more").line.isEmpty)
    }

    @Test func theRhymesAfterTheBarStayHidden() {
        let verse = RhymeDuel.verse(from: "“A cat sat waiting by the door.” | Floor, *more*, four, door, floor, no more.\n\nWant another?")
        #expect(verse.line == "A cat sat waiting by the door.")
        #expect(verse.rhymes == ["floor", "more", "four"], "the line's own word, repeats, and phrases are left out")
        #expect(verse.kept == "A cat sat waiting by the door. | floor, more, four")
        #expect(RhymeDuel.verse(from: verse.kept) == verse)
        #expect(RhymeDuel.verse(from: "The sun came up to greet the day\n| Rhymes: play, stay, may").rhymes == ["play", "stay", "may"])
        #expect(RhymeDuel.verse(from: "The sun came up to greet the day | play stay may").rhymes == ["play", "stay", "may"])
        #expect(RhymeDuel.hints(for: verse).first == "Try ending your line on “floor”.")
    }

    @Test func statusCountsLinesAndEnds() {
        #expect(RhymeDuel.status(linesPlayed: 0) == "Line 1 of 8")
        #expect(RhymeDuel.status(linesPlayed: 7) == "Line 8 of 8")
        #expect(RhymeDuel.status(linesPlayed: 8) == "Duel done")
    }

    @Test func thePromptAsksForShortEndingsANewWordEachLineAndHiddenRhymes() {
        #expect(RhymeDuel.systemPrompt.contains("you go first"))
        #expect(RhymeDuel.systemPrompt.contains("short, common word of one syllable"))
        #expect(RhymeDuel.systemPrompt.contains("end on a new word"))
        #expect(RhymeDuel.systemPrompt.contains("“ | ”"))
        #expect(RhymeDuel.systemPrompt.contains("One line only"))
        #expect(!RhymeDuel.opening.isEmpty)
    }
}

@MainActor
struct RhymeDuelSessionTests {
    private typealias Support = GameTestSupport

    private let opening = "A cat sat waiting by the door"
    /// The opening as the game keeps it, with the rhymes the model hid.
    private let openingReply = "A cat sat waiting by the door | floor, more, four"
    private let exchanges = [
        ("Until the clouds began to pour", "She heard a knock and then a shout"),
        ("A tiny voice said let me out", "A soggy dog stood in the light"),
        ("His fur was dripping, what a sight", "She let him in to share her mat")
    ]
    private let closing = "And that is how he met the cat"

    /// A duel as it is remembered: the model's opening line, the exchanges after it (your line, then the
    /// model's), and your closing line, which gets no reply.
    private func duel(exchanges: [(String, String)] = [], closing: String? = nil) -> ChatSession.PastChat {
        var turns = [Support.turn(cue: RhymeDuel.opening, reply: openingReply)]
        turns += exchanges.map { Support.turn($0.0, reply: $0.1) }
        if let closing { turns.append(Support.turn(closing)) }
        return ChatSession.PastChat(turns: turns, date: .now, mode: .game(.rhymeDuel))
    }

    @Test func startingADuelAsksTheModelToOpen() async {
        let model = ScriptedModel([openingReply])
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
        #expect(session.gameState?.phase == .yourMove(placeholder: "Rhyme with “door”…", hints: RhymeDuel.hints(for: .init(line: opening, rhymes: ["floor", "more", "four"]))))
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
        let model = ScriptedModel(["“She heard a knock and then a shout.”\n\nWant another?"])
        let session = Support.session(model)
        session.reopen(duel())
        await Support.play(exchanges[0].0, in: session)
        #expect(session.turns.last?.answer == "She heard a knock and then a shout.")
        #expect(model.requests.first?.messages.map(\.role) == [.user, .assistant, .user])
        #expect(model.lastMessages == [RhymeDuel.opening, openingReply, exchanges[0].0], "the model sees the rhymes it hid")
    }

    @Test func theModelCarriesTheStoryOnWithANewWord() async throws {
        let model = ScriptedModel(["She heard a knock and then a shout | out, about, doubt, sprout"])
        let session = Support.session(model)
        session.reopen(duel())
        await Support.play(exchanges[0].0, in: session)
        #expect(session.isYourMove)
        #expect(session.gameState?.status == "Line 4 of 8")
        let state = try #require(session.gameState)
        #expect(state.phase == .yourMove(placeholder: "Rhyme with “shout”…", hints: RhymeDuel.hints(for: .init(line: "", rhymes: ["out", "about", "doubt", "sprout"]))))
        #expect(RhymeDuel.lines(for: session.turns).map(\.text) == [opening, exchanges[0].0, exchanges[0].1], "the rhymes stay hidden")
    }

    @Test func aReplyWithoutALineSendsYourLineBack() async {
        let model = ScriptedModel(["| out, about"])
        let session = Support.session(model)
        session.reopen(duel())
        await Support.play(exchanges[0].0, in: session)
        #expect(session.turns.count == 1, "it did not cost a turn")
        #expect(session.draft == exchanges[0].0)
        #expect(session.nudge == RhymeDuel.lostTheThread)
    }

    @Test func aHintShowsOneOfTheModelsRhymesAtATime() throws {
        let session = Support.session(ScriptedModel())
        session.reopen(duel())
        #expect(session.canHint)
        let hints = RhymeDuel.hints(for: .init(line: opening, rhymes: ["floor", "more", "four"]))
        session.hint()
        let first = try #require(session.nudge)
        #expect(hints.contains(first))
        for _ in 0..<10 {
            let shown = session.nudge
            session.hint()
            #expect(session.nudge != shown, "a second hint is a different one")
            #expect(session.nudge.map(hints.contains) == true)
        }
    }

    @Test func noHintsWithoutTheModelsRhymesOrOffYourMove() {
        let session = Support.session(ScriptedModel())
        session.reopen(ChatSession.PastChat(turns: [Support.turn(cue: RhymeDuel.opening, reply: opening)], date: .now, mode: .game(.rhymeDuel)))
        #expect(session.isYourMove)
        #expect(!session.canHint)
        session.reopen(duel(exchanges: exchanges, closing: closing))
        #expect(!session.canHint, "the duel is over")
        session.hint()
        #expect(session.nudge == RhymeDuel.done)
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
