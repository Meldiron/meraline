import AppKit
import Foundation
import Testing
@testable import Meraline

/// The window losing the keyboard (`KeyboardLoss`, `PanelController.windowDidResignKey`): it closes when the
/// person sent the keyboard elsewhere, with a click or a key press since the window was shown or last got one, a
/// switch to another Space, or one of Meraline's own windows, and takes it back when nothing was pressed, since
/// an app coming forward by itself, or an editor taking its window back right after the panel opened, closed it
/// while someone was reading. The keep path is tried on the verdict alone: on the real panel it would take the
/// keyboard from whoever runs the tests.
@MainActor
struct KeyboardLossTests {
    private typealias Support = GameTestSupport

    @Test func theWindowClosesOnlyWhenTheKeyboardWasSentElsewhere() {
        let shown: TimeInterval = 1_000
        let verdict = KeyboardLoss.verdict(ownWindowIsKey:onActiveSpace:lastInputAt:lastPanelInputAt:)
        #expect(verdict(false, true, nil, shown) == .keep, "no click or key press ever")
        #expect(verdict(false, true, shown - 0.4, shown) == .keep, "the ⌥ Space that opened the window, pressed before it took the keyboard")
        #expect(verdict(false, true, shown, shown) == .keep, "the panel's own click, stamped at the same moment")
        #expect(verdict(false, true, shown + 0.005, shown) == .keep, "within the clocks' slack")
        #expect(verdict(false, true, shown + 0.3, shown) == .close("a click or a key press went elsewhere"), "a click in another app, or ⌘Tab")
        #expect(verdict(false, true, shown + 60, shown + 70) == .keep, "the panel got input after the last outside one: typing, then an app came forward by itself")
        #expect(verdict(true, true, nil, shown) == .close("another window of Meraline's took the keyboard"), "Settings, a note, Sparkle's window")
        #expect(verdict(false, false, nil, shown) == .close("the window is on another Space"))
        #expect(verdict(true, false, shown + 5, shown) == .close("another window of Meraline's took the keyboard"), "our own window first, whatever else")
    }

    @Test func theSystemsLastInputIsOnTheUptimeClock() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = KeyboardLoss.lastInputAt(now: now) {
            #expect(last <= now + 0.01 && last > 0, "a click or key press some time before now: \(last) against \(now)")
        }
        #expect(KeyboardLoss.inputTypes == [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown], "clicks and key presses, never moves or scrolls")
    }

    @Test func thePanelStampsTheClicksAndKeyPressesItGets() throws {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        #expect(panel.lastInputAt == 0)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 500, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        panel.sendEvent(click)
        #expect(panel.lastInputAt == 500)
        let move = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 600, windowNumber: panel.windowNumber, context: nil, eventNumber: 2, clickCount: 0, pressure: 0))
        panel.sendEvent(move)
        #expect(panel.lastInputAt == 500, "a move takes no keyboard")
        let earlier = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 400, windowNumber: panel.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1))
        panel.sendEvent(earlier)
        #expect(panel.lastInputAt == 500, "never back in time")
    }

    /// The real panel, ordered front off every screen without the keyboard, as `warmUp` draws it: losing the
    /// keyboard after a click elsewhere closes it a moment later, through the delegate.
    @Test func losingTheKeyboardAfterAClickElsewhereClosesThePanel() async throws {
        let defaults = UserDefaults(suiteName: "MeralineTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: ShortcutSetup.chosenKey)
        let preferences = Support.preferences()
        let session = Support.session(ScriptedModel())
        let updater = Updater(preferences: preferences, defaults: defaults)
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: updater, updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        let panel = controller.panel
        panel.setFrameOrigin(NSPoint(x: -50_000, y: -50_000))
        panel.orderFrontRegardless()
        #expect(panel.isVisible && !panel.isKeyWindow)
        // Shown long ago, so whatever was last clicked or typed on this Mac went elsewhere since.
        panel.lastInputAt = 1
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(controller.isVisible, "the verdict waits a moment for the new key window")
        for _ in 0..<100 where controller.isVisible {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.isVisible, "closed, since a click or a key press went elsewhere")
        for _ in 0..<100 where panel.isVisible {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!panel.isVisible, "and ordered out after the fade")
    }
}
