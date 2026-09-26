import Foundation
import Testing
@testable import Meraline

struct ShakeDetectorTests {
    /// Feeds a drag as a list of (x, y, seconds) positions and returns at which positions a shake completed.
    private func shakes(in positions: [(CGFloat, CGFloat, TimeInterval)], detector: ShakeDetector = ShakeDetector()) -> [Int] {
        var detector = detector
        return positions.enumerated().compactMap { index, position in
            detector.move(to: CGPoint(x: position.0, y: position.1), at: position.2) ? index : nil
        }
    }

    /// A back-and-forth of `swing` points per leg at `hertz` legs a second, sampled every 16 ms like a mouse.
    private func wiggle(legs: Int, swing: CGFloat, hertz: Double, vertical: Bool = false, from start: TimeInterval = 0) -> [(CGFloat, CGFloat, TimeInterval)] {
        var positions: [(CGFloat, CGFloat, TimeInterval)] = [(100, 100, start)]
        var x: CGFloat = 100
        var time = start
        let legDuration = 1 / hertz
        let steps = max(1, Int(legDuration / 0.016))
        for leg in 0..<legs {
            let direction: CGFloat = leg.isMultiple(of: 2) ? 1 : -1
            for _ in 0..<steps {
                x += direction * swing / CGFloat(steps)
                time += legDuration / Double(steps)
                positions.append(vertical ? (100, x, time) : (x, 100, time))
            }
        }
        return positions
    }

    @Test func aQuickShakeIsNoticedOnce() {
        // Four legs of 60 points at 5 legs a second: three turns, then the fourth completes the shake.
        let found = shakes(in: wiggle(legs: 5, swing: 60, hertz: 5))
        #expect(found.count == 1)
        let positions = wiggle(legs: 5, swing: 60, hertz: 5)
        #expect(positions[found[0]].2 < 1.0)
    }

    @Test func aVerticalOrDiagonalShakeCountsToo() {
        #expect(shakes(in: wiggle(legs: 5, swing: 60, hertz: 5, vertical: true)).count == 1)
        let diagonal = wiggle(legs: 5, swing: 60, hertz: 5).map { ($0.0, $0.0, $0.2) }
        #expect(shakes(in: diagonal).count == 1)
    }

    @Test func aSlowWiggleIsNotAShake() {
        // One leg every 0.7 seconds: the four turns never fall within the window.
        #expect(shakes(in: wiggle(legs: 6, swing: 60, hertz: 1 / 0.7)).isEmpty)
    }

    @Test func aTrembleIsNotAShake() {
        // Fast, but 4 points a leg: never far enough to count as a turn.
        #expect(shakes(in: wiggle(legs: 20, swing: 4, hertz: 10)).isEmpty)
    }

    @Test func aPlainDragIsNotAShake() {
        var drag: [(CGFloat, CGFloat, TimeInterval)] = []
        for step in 0..<60 {
            let x = CGFloat(100 + step * 8)
            let y = CGFloat(100 + step * 3)
            drag.append((x, y, TimeInterval(step) * 0.016))
        }
        #expect(shakes(in: drag).isEmpty)
        // Dragging somewhere and dragging back is one turn, not a shake.
        #expect(shakes(in: wiggle(legs: 2, swing: 200, hertz: 4)).isEmpty)
    }

    @Test func aTrembleDoesNotBreakASwing() {
        // Right 30 points with a one-point step back in the middle still counts as one swing.
        var detector = ShakeDetector()
        var found = false
        let legs: [(CGFloat, TimeInterval)] = [(100, 0), (115, 0.05), (114, 0.06), (130, 0.1), (100, 0.2), (130, 0.3), (100, 0.4), (130, 0.5)]
        for (x, time) in legs {
            if detector.move(to: CGPoint(x: x, y: 100), at: time) { found = true }
        }
        #expect(found)
    }

    @Test func lettingGoStartsOver() {
        // Two turns, a pause longer than a drag ever has, then two more: the pause forgets the first two.
        let first = wiggle(legs: 3, swing: 60, hertz: 5)
        let second = wiggle(legs: 3, swing: 60, hertz: 5, from: first.last!.2 + 1)
        #expect(shakes(in: first + second).isEmpty)
        // The same legs without the pause make a shake.
        #expect(shakes(in: wiggle(legs: 6, swing: 60, hertz: 5)).count == 1)
    }

    @Test func aSpentShakeNeedsFreshTurns() {
        // Shaking on after a shake completes makes another only after four more turns.
        let found = shakes(in: wiggle(legs: 10, swing: 60, hertz: 5))
        #expect(found.count == 2)
    }

    @Test func standingStillChangesNothing() {
        var detector = ShakeDetector()
        var moved = false
        for _ in 0..<50 {
            let shaken = detector.move(to: CGPoint(x: 100, y: 100), at: 0.1)
            moved = moved || shaken
        }
        #expect(!moved)
    }
}
