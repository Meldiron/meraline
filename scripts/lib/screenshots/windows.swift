import CoreGraphics
import Foundation

// Lists one window of a process. Usage: windows <pid> panel|settings|note, or windows screen
// panel    → "x y width height" of the 704-point-wide floating panel
// settings → "id x y width height" of the 715-point-wide Settings window
// note     → "x y width height" of an answer torn off into a note: any other window of a note's size
// screen   → "width height" of the main display, in points
if CommandLine.arguments[1] == "screen" {
    let bounds = CGDisplayBounds(CGMainDisplayID())
    print(Int(bounds.width), Int(bounds.height))
    exit(0)
}
let pid = Int32(CommandLine.arguments[1])!
let wanted = CommandLine.arguments[2]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    let b = w[kCGWindowBounds as String] as! [String: CGFloat]
    let id = w[kCGWindowNumber as String]!
    if wanted == "panel" && b["Width"] == 704 { print(Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!)); break }
    if wanted == "settings" && b["Width"] == 715 { print(id, Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!)); break }
    if wanted == "note", let width = b["Width"], let height = b["Height"], width != 704, width != 715, width > 200, height > 100 {
        print(Int(b["X"]!), Int(b["Y"]!), Int(width), Int(height)); break
    }
}
