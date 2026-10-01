import AppKit
import SwiftUI
import Testing
@testable import Meraline

/// The card of the decisions about each word or line (`BulkDecisionCard`), and the answers the panel keeps open.
@MainActor
struct BulkDecisionCardTests {
    private static func batch() -> DecisionBatch {
        func yes(_ p: Double) -> Decision { Decision(options: [.init(label: "Yes", probability: p), .init(label: "No", probability: 1 - p)], isYesNo: true, confidence: abs(2 * p - 1)) }
        let lines = ["Renew the lease", "Order coffee", "Reply to legal", "Book the dinner"]
        return DecisionBatch(scope: .lines, answers: .yesNo, total: lines.count, items: zip(lines, [0.92, 0.06, 0.86, 0.11]).enumerated().map { index, pair in
            DecisionBatch.Item(id: index, text: pair.0, decision: yes(pair.1))
        })
    }

    private static func height(open: Set<DecisionBatch.Group.ID>) -> CGFloat {
        NSHostingView(rootView: BulkDecisionCard(batch: batch(), unsureBelow: 0.5, isAnswering: false, openGroups: open).frame(width: 500)).fittingSize.height
    }

    @Test func everyAnswerStartsFoldedToItsHeader() throws {
        let groups = Self.batch().groups(unsureBelow: 0.5)
        #expect(groups.map(\.label) == ["Yes", "No"])
        let folded = Self.height(open: [])
        let yesOpen = Self.height(open: [groups[0].id])
        let allOpen = Self.height(open: Set(groups.map(\.id)))
        #expect(yesOpen > folded + 20, "opening Yes shows its two lines under the header")
        #expect(allOpen > yesOpen + 20, "opening No shows its two lines too")
    }

    @Test func thePanelKeepsTheOpenAnswersByTurn() {
        let layout = PanelLayout()
        let first = UUID(), second = UUID()
        layout.toggleDecisionGroup("answer.Yes", of: first)
        #expect(layout.openDecisionGroups(of: first) == ["answer.Yes"])
        #expect(layout.openDecisionGroups(of: second).isEmpty, "another turn's answers stay folded")
        layout.toggleDecisionGroup("unsure", of: first)
        #expect(layout.openDecisionGroups(of: first) == ["answer.Yes", "unsure"])
        layout.toggleDecisionGroup("answer.Yes", of: first)
        #expect(layout.openDecisionGroups(of: first) == ["unsure"], "a second click folds it back")
    }
}
