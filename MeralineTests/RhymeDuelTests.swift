import AppKit
import Foundation
import Testing
@testable import Meraline

struct RhymeDuelRulesTests {
    private typealias Support = GameTestSupport

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
        #expect(!RhymeDuel.rhymes("group", with: "stoop"), "spelling alone misses this one")
        #expect(RhymeDuel.family(of: "stoop") == nil)
        let bare = RhymeDuel.Verse(line: "A cat sat waiting on the stoop")
        let hinted = RhymeDuel.Verse(line: bare.line, rhymes: ["group", "loop"])
        #expect(RhymeDuel.complaint(about: "She waited for the group", after: bare) != nil)
        #expect(RhymeDuel.complaint(about: "She waited for the Group!", after: hinted) == nil)
        #expect(RhymeDuel.complaint(about: "And had a bowl of soup", after: bare) != nil)
        #expect(RhymeDuel.complaint(about: "And had a bowl of soup", after: .init(line: bare.line, rhymes: ["group"])) == nil, "by way of “group”")
        #expect(RhymeDuel.complaint(about: "And then I saw the sun", after: hinted)?.contains("“stoop”") == true)
    }

    @Test func aWordOfTheEndingsFamilyCountsToo() {
        #expect(!RhymeDuel.rhymes("more", with: "door"), "spelling alone misses this one")
        let bare = RhymeDuel.Verse(line: "A cat sat waiting by the door")
        #expect(RhymeDuel.complaint(about: "She wanted nothing more", after: bare) != nil, "only words known to rhyme count")
        let opening = RhymeDuel.Verse(line: bare.line, rhymes: RhymeDuel.rhymes(for: bare))
        #expect(RhymeDuel.complaint(about: "She wanted nothing more", after: opening) == nil)
        #expect(RhymeDuel.complaint(about: "Until the clouds began to pour", after: opening) == nil)
        #expect(RhymeDuel.complaint(about: "And then I saw the sun", after: opening)?.contains("“door”") == true)
        let rhymes = RhymeDuel.rhymes(for: .init(line: opening.line, rhymes: ["floor", "adore"]))
        #expect(rhymes.prefix(2) == ["floor", "adore"], "the model's own come first")
        #expect(rhymes.contains("more"))
        #expect(!rhymes.contains("door"), "not the word to rhyme with")
        #expect(rhymes.filter { $0 == "floor" }.count == 1)
    }

    @Test func theFamiliesAreDifferentSoundsWithRoomForHints() {
        var seen: Set<String> = []
        for family in RhymeDuel.families {
            #expect(family.count >= RhymeDuel.offered + 3, "\(family[0]) needs words to offer and to hint")
            for word in family {
                #expect(word.allSatisfy { $0.isLowercase && $0.isLetter }, "\(word)")
                #expect(seen.insert(word).inserted, "\(word) is in two families")
                #expect(RhymeDuel.family(of: word) == family)
            }
        }
        for (index, family) in RhymeDuel.families.enumerated() {
            for other in RhymeDuel.families[(index + 1)...] {
                #expect(!RhymeDuel.rhymes(family[0], with: other[0]), "\(family[0]) and \(other[0]) sound alike")
            }
        }
    }

    @Test func aNewDuelGetsAStoryAndThreeWordsOfOneSound() throws {
        for seed: UInt64 in 0..<50 {
            var dice = GameDice(seed: seed)
            let cue = Support.turn(cue: seed.isMultiple(of: 2) ? RhymeDuel.opening : RhymeDuel.rematchCue)
            let aside = try #require(RhymeDuel.aside(for: cue, after: [], in: .english, dice: &dice))
            #expect(aside.hasPrefix("This duel’s story: "))
            #expect(aside.contains(". Make it "))
            let words = try offered(in: aside)
            #expect(words.count == RhymeDuel.offered)
            #expect(Set(words).count == words.count)
            let family = try #require(RhymeDuel.family(of: words[0]))
            #expect(words.allSatisfy(family.contains), "one sound: \(words)")
        }
    }

    @Test func theStoriesAndSoundsVaryFromDuelToDuel() throws {
        var dice = GameDice(seed: 7)
        var stories: Set<String> = []
        var sounds: Set<String> = []
        for _ in 0..<20 {
            let aside = try #require(RhymeDuel.aside(for: Support.turn(cue: RhymeDuel.opening), after: [], in: .english, dice: &dice))
            stories.insert(String(aside.prefix { $0 != "." }))
            sounds.insert(try #require(RhymeDuel.family(of: try offered(in: aside)[0]))[0])
        }
        #expect(stories.count == 20)
        #expect(sounds.count >= 12)
    }

    @Test func theModelsNextWordsRhymeWithNoLineSoFar() throws {
        let duel = [
            Support.turn(cue: RhymeDuel.opening, reply: "A cat sat waiting by the door | floor, more"),
            Support.turn("Until the clouds began to pour", reply: "She heard a knock and then a shout | out, doubt")
        ]
        for seed: UInt64 in 0..<100 {
            var dice = GameDice(seed: seed)
            let aside = try #require(RhymeDuel.aside(for: Support.turn("A tiny voice said let me out"), after: duel, in: .english, dice: &dice))
            #expect(aside.hasPrefix("End your line on one of these words: "), "no new story mid-duel")
            let family = try #require(RhymeDuel.family(of: try offered(in: aside)[0]))
            #expect(!family.contains("door") && !family.contains("shout"), "\(family[0])")
        }
    }

    @Test func aRematchAvoidsTheSoundsOfEarlierDuelsWhileItCan() throws {
        let earlier = RhymeDuel.families.prefix(RhymeDuel.families.count - 1).map { family in
            Support.turn(family[0], reply: "And so it went on to the \(family[1])")
        }
        let turns = [Support.turn(cue: RhymeDuel.opening, reply: "It all began one sunny day")] + earlier
        let left = try #require(RhymeDuel.families.last)
        for seed: UInt64 in 0..<10 {
            var dice = GameDice(seed: seed)
            let aside = try #require(RhymeDuel.aside(for: Support.turn(cue: RhymeDuel.rematchCue), after: turns, in: .english, dice: &dice))
            #expect(try offered(in: aside).allSatisfy(left.contains), "the one sound the chat hasn't heard")
        }
    }

    /// The words an aside offers the model to end its line on.
    private func offered(in aside: String) throws -> [String] {
        let list = try #require(aside.components(separatedBy: "End your line on one of these words: ").last)
        return list.dropLast().components(separatedBy: ", ")
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

    @Test func thePromptAsksForShortLinesShortEndingsANewWordEachLineAndHiddenRhymes() {
        #expect(RhymeDuel.systemPrompt.contains("Whoever opens the duel sets each rhyme"))
        #expect(RhymeDuel.systemPrompt.contains("four beats"), "the measure of nursery rhymes and ballads")
        #expect(RhymeDuel.systemPrompt.contains("about eight syllables and rarely more than nine words"))
        #expect(RhymeDuel.systemPrompt.contains("keep your own line short whatever the length of theirs"))
        #expect(RhymeDuel.systemPrompt.contains("Choose the ending first"))
        #expect(RhymeDuel.systemPrompt.contains("When the user opens, answer each of the user's lines"))
        #expect(RhymeDuel.systemPrompt.contains("the subject the message gives"))
        #expect(RhymeDuel.systemPrompt.contains("Each message names a few words your line may end on"))
        #expect(!RhymeDuel.systemPrompt.contains("at random"), "the model can't pick at random; this Mac draws")
        #expect(RhymeDuel.systemPrompt.contains("short, common word of one syllable"))
        #expect(RhymeDuel.systemPrompt.contains("ends on a new word, one that rhymes with none of the lines so far"))
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

    @Test func aDuelWaitsForYouOrTheModelToOpen() async throws {
        let model = ScriptedModel([openingReply])
        let session = Support.session(model)
        session.draft = "half a question"
        session.startGame(.rhymeDuel)
        #expect(session.game == .rhymeDuel)
        #expect(session.draft.isEmpty)
        #expect(!session.isStreaming, "nobody has opened yet")
        #expect(model.requests.isEmpty)
        #expect(session.gameState?.isOpening == true)
        #expect(session.gameState?.opening?.button == RhymeDuel.randomButton)
        #expect(session.canSend, "Return with nothing typed lets the model open")
        #expect(session.nudge == RhymeDuel.invitation)

        session.choose(RhymeDuel.randomButton)
        #expect(session.isStreaming)
        #expect(session.turns.first?.cue == RhymeDuel.opening)
        #expect(model.requests.first?.systemPrompt == RhymeDuel.systemPrompt)
        let asked = try #require(session.turns.first?.message)
        #expect(asked.hasPrefix("\(RhymeDuel.opening)\n\nThis duel’s story: "), "the story is drawn on this Mac")
        #expect(model.lastMessages == [asked])
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
        #expect(!session.failureNeedsSettings, "nothing is asked until someone opens")
        session.send()
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

    @Test func theModelsLineIsCleanedUp() async throws {
        let model = ScriptedModel(["“She heard a knock and then a shout.”\n\nWant another?"])
        let session = Support.session(model)
        session.reopen(duel())
        await Support.play(exchanges[0].0, in: session)
        #expect(session.turns.last?.answer == "She heard a knock and then a shout.")
        #expect(model.requests.first?.messages.map(\.role) == [.user, .assistant, .user])
        let asked = try #require(session.turns.last?.message)
        #expect(asked.hasPrefix("\(exchanges[0].0)\n\nEnd your line on one of these words: "))
        #expect(model.lastMessages == [RhymeDuel.opening, openingReply, asked], "the model sees the rhymes it hid")
    }

    @Test func theTurnKeepsWhatWasDrawnForTheModelToReadAgain() async throws {
        let model = ScriptedModel([openingReply, "She heard a knock and then a shout | out, about"])
        let session = Support.session(model)
        session.dice = GameDice(seed: 3)
        session.startGame(.rhymeDuel)
        session.send()
        await Support.settle(session)
        let asked = try #require(session.turns.first?.message)
        await Support.play(exchanges[0].0, in: session)
        #expect(model.lastMessages == [asked, openingReply, try #require(session.turns.last?.message)], "a live agent follows on from the same words")
        #expect(RhymeDuel.lines(for: session.turns).map(\.text) == [opening, exchanges[0].0, exchanges[0].1], "what was drawn never shows")
        #expect(session.conversationMarkdown?.contains("story") == false)
    }

    @Test func whenYouOpenYouSetTheRhymesAndTheModelAnswersThem() async throws {
        let model = ScriptedModel([
            "Until the clouds began to pour | more, four",
            "A soggy dog stood in the light",
            "It chased a mouse and then it sat", "And ate its supper on a tray"
        ])
        let session = Support.session(model)
        session.dice = GameDice(seed: 4)
        session.startGame(.rhymeDuel)
        await Support.play(opening, in: session)
        let first = try #require(session.turns.first)
        #expect(first.cue == RhymeDuel.yourOpening)
        #expect(first.question == opening)
        let asked = first.message
        #expect(asked.hasPrefix("\(RhymeDuel.yourOpening)\n\n\(opening)\n\nEnd your line on one of these words: "))
        let offered = try #require(asked.components(separatedBy: "one of these words: ").last).dropLast().components(separatedBy: ", ")
        #expect(offered.count == RhymeDuel.offered)
        #expect(offered.allSatisfy { RhymeDuel.family(of: "door")?.contains($0) == true && $0 != "door" }, "rhymes for your line")
        #expect(!asked.contains("story:"), "your line sets the story")
        #expect(session.gameState?.phase == .yourMove(placeholder: "Carry the story on, ending on a new sound…"))
        #expect(!session.canHint)
        #expect(RhymeDuel.lines(for: session.turns).map(\.text) == [opening, "Until the clouds began to pour"])

        await Support.play("The rain kept falling on the floor", in: session)
        #expect(session.nudge?.contains("“floor” sounds like “door”") == true, "a new sound for each couplet")
        #expect(model.requests.count == 1)
        await Support.play("She heard a knock, a bark, a bite", in: session)
        #expect(model.lastMessages.last?.hasPrefix("She heard a knock, a bark, a bite\n\nEnd your line on one of these words: ") == true)
        await Support.play("A tiny kitten, gray and flat", in: session)
        #expect(session.gameState?.status == "Line 7 of 8")
        await Support.play("It dreamed of fish, and far away", in: session)
        #expect(model.requests.count == 4, "the model answers your last line too")
        #expect(session.gameState?.status == "Duel done")
        #expect(session.nudge == RhymeDuel.doneByModel)
        #expect(session.history.isEmpty)
        session.reset()
        #expect(session.history.first?.title == "Rhyme Duel: \(opening)")
    }

    @Test func aLineTypedOnceADuelIsOverOpensTheNext() async throws {
        let model = ScriptedModel(["It found a friend, and that was that"])
        let session = Support.session(model)
        session.reopen(duel(exchanges: exchanges, closing: closing))
        guard case .over(_, let next)? = session.gameState?.phase else {
            Issue.record("the duel should be over")
            return
        }
        #expect(next.takesYourMove)
        await Support.play("A robot lived beneath the sea", in: session)
        #expect(session.turns.last?.cue == RhymeDuel.yourOpening)
        #expect(session.turns.last?.question == "A robot lived beneath the sea")
        #expect(session.gameState?.status == "Line 3 of 8")
        #expect(RhymeDuel.lines(for: session.turns).map(\.text).suffix(3) == ["Rematch", "A robot lived beneath the sea", "It found a friend, and that was that"])
    }

    @Test func theModelCarriesTheStoryOnWithANewWord() async throws {
        let model = ScriptedModel(["She heard a knock and then a shout | out, about, doubt, sprout"])
        let session = Support.session(model)
        session.reopen(duel())
        await Support.play(exchanges[0].0, in: session)
        #expect(session.isYourMove)
        #expect(session.gameState?.status == "Line 4 of 8")
        let state = try #require(session.gameState)
        let offered = RhymeDuel.rhymes(for: .init(line: "and then a shout", rhymes: ["out", "about", "doubt", "sprout"]))
        #expect(state.phase == .yourMove(placeholder: "Rhyme with “shout”…", hints: RhymeDuel.hints(for: .init(line: "", rhymes: offered))), "the line ended on a word it was offered")
        #expect(state.hints.contains("Try ending your line on “scout”."), "the family of “shout” helps out")
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

    @Test func noHintsWithoutAnyKnownRhymesOrOffYourMove() {
        let session = Support.session(ScriptedModel())
        session.reopen(ChatSession.PastChat(turns: [Support.turn(cue: RhymeDuel.opening, reply: "A cat sat waiting on the stoop")], date: .now, mode: .game(.rhymeDuel)))
        #expect(session.isYourMove)
        #expect(!session.canHint)
        session.reopen(duel(exchanges: exchanges, closing: closing))
        #expect(!session.canHint, "the duel is over")
        session.hint()
        #expect(session.nudge == RhymeDuel.done)
    }

    @Test func theLastWordIsYoursAndReturnStartsARematch() throws {
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
        let rematch = try #require(session.turns.last?.message)
        #expect(rematch.hasPrefix("\(RhymeDuel.rematchCue)\n\nThis duel’s story: "))
        #expect(model.requests.last?.messages.last?.text == "\(closing)\n\n\(rematch)", "two user messages in a row are joined")
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
}
