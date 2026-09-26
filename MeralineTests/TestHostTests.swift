import AppKit
import Testing
@testable import Meraline

/// The app that hosts the tests must not start Meraline: it read the API keys from the Keychain, which asked
/// for the password on every run of an ad-hoc signed test build, and it took the shortcut from the real app.
@MainActor
struct TestHostTests {
    @Test func knowsItHostsTheTests() {
        #expect(MeralineApp.isHostingTests)
    }

    @Test func startsNoAppDelegate() {
        #expect(NSApp.delegate == nil)
    }
}
