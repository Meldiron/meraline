import AppKit

// A full-screen gradient behind Meraline's floating panel, so screenshots never show other windows.
// Usage: backdrop dark|light [above]
// "above" puts it over every normal window, so no app that comes forward can cover it; Meraline's floating
// panel and its menus stay on top. Without it the backdrop is a normal window, which Settings can open over.
let light = CommandLine.arguments.dropFirst().first == "light"
let above = CommandLine.arguments.dropFirst(2).first == "above"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main ?? NSScreen.screens[0]
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = above ? NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1) : .normal
window.isOpaque = true
window.hasShadow = false
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
let gradient = CAGradientLayer()
gradient.frame = CGRect(origin: .zero, size: screen.frame.size)
gradient.startPoint = CGPoint(x: 0, y: 1)
gradient.endPoint = CGPoint(x: 1, y: 0)
gradient.colors = light
    ? [NSColor(red: 0.96, green: 0.93, blue: 0.97, alpha: 1).cgColor, NSColor(red: 0.88, green: 0.90, blue: 0.98, alpha: 1).cgColor, NSColor(red: 0.98, green: 0.91, blue: 0.94, alpha: 1).cgColor]
    : [NSColor(red: 0.13, green: 0.10, blue: 0.22, alpha: 1).cgColor, NSColor(red: 0.09, green: 0.10, blue: 0.20, alpha: 1).cgColor, NSColor(red: 0.20, green: 0.10, blue: 0.19, alpha: 1).cgColor]
let view = NSView(frame: window.contentRect(forFrameRect: screen.frame))
view.wantsLayer = true
view.layer = gradient
window.contentView = view
window.orderFrontRegardless()
app.run()
