import CoreGraphics
import Foundation

/// Notices the window being shaken: dragged back and forth quickly, the way a window is shaken to clear
/// a desktop. `PanelController` hands it the window's origin on every move and forgets the recent chats
/// when it says so. Everything is worked out from the positions and their times, so a test can feed it a
/// drag of its own.
///
/// A shake is `reversals` changes of direction within `window` seconds, each after a swing of at least
/// `minimumSwing` points, in whatever direction the window goes. A drag from here to there reverses
/// rarely, and the tremble of a hand never swings far enough to count.
nonisolated struct ShakeDetector: Sendable {
    /// How far the window must travel one way before turning back counts.
    var minimumSwing: CGFloat = 20
    /// How many turns make a shake: four is two full back-and-forths.
    var reversals = 4
    /// How recent every one of those turns must be.
    var window: TimeInterval = 1.2
    /// A pause this long between two positions starts over: the window was let go and picked up again.
    var pause: TimeInterval = 0.6

    private var last: (point: CGPoint, time: TimeInterval)?
    /// The way the window has gone since it last turned, added up.
    private var swing = CGVector(dx: 0, dy: 0)
    /// When the window turned, most recent last.
    private var turns: [TimeInterval] = []

    /// Notes where the window is now. True once, at the move that completes a shake; the shake is then
    /// spent, and only a fresh set of turns makes another.
    mutating func move(to point: CGPoint, at time: TimeInterval) -> Bool {
        defer { last = (point, time) }
        guard let last, time - last.time <= pause else {
            swing = CGVector(dx: 0, dy: 0)
            turns = []
            return false
        }
        let delta = CGVector(dx: point.x - last.point.x, dy: point.y - last.point.y)
        guard delta.dx != 0 || delta.dy != 0 else { return false }
        let turnedBack = swing.dx * delta.dx + swing.dy * delta.dy < 0
        if turnedBack, hypot(swing.dx, swing.dy) >= minimumSwing {
            swing = delta
            turns.append(time)
            turns.removeAll { time - $0 > window }
            if turns.count >= reversals {
                turns = []
                swing = CGVector(dx: 0, dy: 0)
                return true
            }
        } else {
            swing.dx += delta.dx
            swing.dy += delta.dy
        }
        return false
    }
}
