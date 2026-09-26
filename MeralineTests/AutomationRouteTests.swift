import Foundation
import Testing
@testable import Meraline

struct AutomationRouteTests {
    @Test func askWithTextAndSend() {
        let route = AutomationRoute(url: URL(string: "meraline://ask?text=What%20is%20a%20monad%3F&send=1")!)
        #expect(route == .ask(text: "What is a monad?", send: true))
    }

    @Test func askAloneJustOpens() {
        #expect(AutomationRoute(url: URL(string: "meraline://ask")!) == .ask(text: nil, send: false))
        #expect(AutomationRoute(url: URL(string: "meraline://")!) == .ask(text: nil, send: false))
        #expect(AutomationRoute(url: URL(string: "meraline://ask?text=%20%20")!) == .ask(text: nil, send: false))
    }

    @Test func sendAcceptsSeveralSpellings() {
        for value in ["1", "true", "YES"] {
            #expect(AutomationRoute(url: URL(string: "meraline://ask?text=hi&send=\(value)")!) == .ask(text: "hi", send: true))
        }
        #expect(AutomationRoute(url: URL(string: "meraline://ask?text=hi&send=0")!) == .ask(text: "hi", send: false))
    }

    @Test func otherRoutes() {
        #expect(AutomationRoute(url: URL(string: "meraline://new")!) == .newChat)
        #expect(AutomationRoute(url: URL(string: "MERALINE://Settings")!) == .settings(pane: nil))
        #expect(AutomationRoute(url: URL(string: "meraline://settings?pane=claudeCode")!) == .settings(pane: "claudeCode"))
    }

    @MainActor @Test func settingsPanesByName() {
        #expect(SettingsPane(named: "claudecode") == .provider(.claudeCode))
        #expect(SettingsPane(named: "Updates") == .softwareUpdate)
        #expect(SettingsPane(named: "about") == .about)
        #expect(SettingsPane(named: "nowhere") == nil)
    }

    @Test func rejectsForeignSchemesAndUnknownRoutes() {
        #expect(AutomationRoute(url: URL(string: "https://example.com/ask")!) == nil)
        #expect(AutomationRoute(url: URL(string: "meraline://dance")!) == nil)
    }
}
