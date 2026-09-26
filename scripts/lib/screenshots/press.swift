import ApplicationServices
import CoreGraphics
import Foundation

// Presses the left mouse button at a screen point (top-left origin, in points) and holds it for a
// while before releasing. A long hold keeps a menu open for a screenshot; a short one is a click.
// Usage: press x y [seconds], or press move x y to only move the pointer there (out of the way of
// tooltips), or press scroll x y points to scroll the view under x y down by that much, or press
// button pid title to click the middle of the first button of that process whose title or
// description starts with title (through Accessibility, so no coordinates go stale).
if CommandLine.arguments[1] == "button" {
    let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[2])!)
    let wanted = CommandLine.arguments[3]
    func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    func find(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 40 { return nil }
        if value(element, kAXRoleAttribute) as? String == kAXButtonRole,
           [kAXTitleAttribute, kAXDescriptionAttribute].contains(where: { (value(element, $0) as? String)?.hasPrefix(wanted) == true }) {
            return element
        }
        for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let found = find(child, depth: depth + 1) { return found }
        }
        return nil
    }
    let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard let button = windows.lazy.compactMap({ find($0) }).first,
          let position = value(button, kAXPositionAttribute), let size = value(button, kAXSizeAttribute) else {
        FileHandle.standardError.write(Data("No button titled \(wanted)\n".utf8))
        exit(1)
    }
    var origin = CGPoint.zero, extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    let point = CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)
    let source = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }
    exit(0)
}
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
