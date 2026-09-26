import CoreGraphics
import Foundation

// Presses the left mouse button at a screen point (top-left origin, in points) and holds it for a
// while before releasing. A long hold keeps a menu open for a screenshot; a short one is a click.
// Usage: press x y [seconds], or press move x y to only move the pointer there (out of the way of
// tooltips), or press scroll x y points to scroll the view under x y down by that much.
if CommandLine.arguments[1] == "scroll" {
    let point = CGPoint(x: Double(CommandLine.arguments[2])!, y: Double(CommandLine.arguments[3])!)
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.2)
    var remaining = Int32(CommandLine.arguments[4])!
    while remaining > 0 {
        let step = min(remaining, 60)
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        remaining -= step
        Thread.sleep(forTimeInterval: 0.02)
    }
    exit(0)
}
if CommandLine.arguments[1] == "move" {
    let point = CGPoint(x: Double(CommandLine.arguments[2])!, y: Double(CommandLine.arguments[3])!)
    CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    exit(0)
}
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
