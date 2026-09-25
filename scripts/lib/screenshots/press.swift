import CoreGraphics
import Foundation

// Presses the left mouse button at a screen point (top-left origin, in points) and holds it for a
// while before releasing. A long hold keeps a menu open for a screenshot; a short one is a click.
// Usage: press x y [seconds]
let x = Double(CommandLine.arguments[1])!
let y = Double(CommandLine.arguments[2])!
let hold = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 0.1
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
post(.mouseMoved)
Thread.sleep(forTimeInterval: 0.15)
post(.leftMouseDown)
Thread.sleep(forTimeInterval: hold)
post(.leftMouseUp)
