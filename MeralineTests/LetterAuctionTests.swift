import Foundation
import Testing
@testable import Meraline

@MainActor
struct LetterAuctionTests {
    private typealias Support = GameTestSupport

    private static let deal = "R A T E S L I N O P K Y U D E | slink, pure, tray, dote, ask"

    @Test func dealsInMostShapes() throws {
        let deal = try #require(LetterAuction.deal(from: Self.deal))
        #expect(String(deal.letters) == "rateslinopkyude")
        #expect(deal.words == ["slink", "pure", "tray", "dote", "ask"])
        #expect(LetterAuction.deal(from: "Pool: R, A, T, E, S, L, I, N, O, P, K, Y, U, D, E")?.letters == deal.letters)
        #expect(LetterAuction.deal(from: "RATESLINOPKYUDE")?.letters == deal.letters)
        #expect(LetterAuction.deal(from: "R A T") == nil, "too few letters")
        #expect(LetterAuction.deal(from: "B C D F G H J K L M N P") == nil, "no vowels")
    }

    @Test func thePoolPaysForAWordOnlyOnce() {
        let pool = Array("ratesliopkyude")
        #expect(LetterAuction.spending("keep", from: Array("keap")) == nil, "one E short")
        #expect(LetterAuction.spending("slope", from: pool).map { String($0) } == "ratikyude")
        #expect(LetterAuction.shortfall(of: "quiz", in: pool) == ["Q", "Z"])
        #expect(LetterAuction.worth(of: "slink") == 9)
        #expect(LetterAuction.worth(of: "quiz") == 22)
    }

    @Test func yourWordIsCheckedBeforeAsking() {
        let turns = [Support.turn(cue: LetterAuction.opening, reply: Self.deal)]
        #expect(LetterAuction.play("Slink!", in: turns, insisting: false) == .ask("slink"))
        #expect(LetterAuction.play("quiz", in: turns, insisting: false) == .reject("The pool can’t pay for “QUIZ”: it’s short of “Q” and “Z”."))
        #expect(LetterAuction.play("a", in: turns, insisting: false) == .reject("Spend at least two letters."))
        #expect(LetterAuction.play("red tape", in: turns, insisting: false) == .reject("One word at a time."))
        #expect(LetterAuction.play("pass", in: turns, insisting: false)
            == .record("pass", outcome: GameOutcome(text: "You closed the bank. A draw, 0 all.", youWon: nil)))
    }

    @Test func theBankerDealsJudgesAndPlays() async {
        let model = ScriptedModel([Self.deal, "OK: tray", "NO: that isn’t a word", "OK: zebra"])
        let session = Support.session(model)
        session.startGame(.letterAuction)
        await Support.settle(session)
        #expect(model.requests.first?.systemPrompt == LetterAuction.systemPrompt)
        #expect(session.gameState?.status == "15 letters left · You 0, Banker 0")
        #expect(session.gameState?.hints == ["Try “SLINK”, worth 9.", "Try “PURE”, worth 6.", "Try “TRAY”, worth 7.", "Try “DOTE”, worth 5.", "Try “ASK”, worth 7."])

        await Support.play("slink", in: session)
        #expect(session.turns.last?.answer == "OK: tray | left: E O P U D E", "the banker reads the pool next time")
        #expect(session.gameState?.status == "6 letters left · You 9, Banker 7")
        #expect(session.gameState?.hints == [], "none of the deal’s words fit what’s left")

        await Support.play("oped", in: session)
        #expect(session.nudge == "The banker says no: That isn’t a word.")
        #expect(session.draft == "oped")

        await Support.play("dope", in: session)
        #expect(session.gameState?.status == "2 letters left · You 16, Banker 7", "a word the pool can’t pay for banks nothing")
        #expect(LetterAuction.lines(for: session.turns).map(\.text) == [
            "The banker deals",
            "R¹ A¹ T¹ E¹ S¹ L¹ I¹ N¹ O¹ P³ K⁵ Y⁴ U¹ D² E¹",
            "SLINK +9 · TRAY +7 · DOPE +7 · ZEBRA, not in the pool"
        ])

        await Support.play("pass", in: session)
        #expect(session.nudge == "You closed the bank. You win, 16 to 7.")
        guard case .over(let outcome, _)? = session.gameState?.phase else {
            Issue.record("pass should close the bank")
            return
        }
        #expect(outcome.youWon == true)
    }

    @Test func theGameEndsWhenThePoolRunsDry() {
        let turns = [
            Support.turn(cue: LetterAuction.opening, reply: "C A T S D O G E I N"),
            Support.turn("cats", reply: "OK: dingo")
        ]
        let auction = LetterAuction.review(turns)
        #expect(auction.left == ["e"])
        #expect(auction.ending == GameOutcome(text: "The pool is spent. The banker wins, 7 to 6.", youWon: false))
    }
}
