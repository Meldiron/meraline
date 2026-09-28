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

    @Test func askWithASelection() {
        let route = AutomationRoute(url: URL(string: "meraline://ask?selection=Bonjour%20tout%20le%20monde&text=Translate&send=1")!)
        #expect(route == .ask(text: "Translate", selection: "Bonjour tout le monde", send: true))
        #expect(AutomationRoute(url: URL(string: "meraline://ask?selection=%20")!) == .ask(text: nil, send: false))
    }

    @Test func askWithTheClipboardAndTheScreen() {
        let route = AutomationRoute(url: URL(string: "meraline://ask?text=What%20is%20this%3F&clipboard=1&screen=true&send=1")!)
        #expect(route == .ask(text: "What is this?", clipboard: true, screen: true, send: true))
        #expect(AutomationRoute(url: URL(string: "meraline://ask?screen=1")!) == .ask(text: nil, screen: true, send: false))
        #expect(AutomationRoute(url: URL(string: "meraline://ask?clipboard=0&screen=no")!) == .ask(text: nil, send: false))
    }

    @Test func askAnAgentOrAnLLM() {
        #expect(AutomationRoute(url: URL(string: "meraline://ask?text=hi&agent=1")!) == .ask(text: "hi", mode: .agent, send: false))
        #expect(AutomationRoute(url: URL(string: "meraline://ask?text=hi&agent=off")!) == .ask(text: "hi", mode: .llm, send: false))
        #expect(AutomationRoute(url: URL(string: "meraline://ask?text=hi&agent=maybe")!) == .ask(text: "hi", send: false))
    }

    @Test func switchMode() {
        #expect(AutomationRoute(url: URL(string: "meraline://mode?agent=1")!) == .mode(.agent))
        #expect(AutomationRoute(url: URL(string: "meraline://mode?agent=FALSE")!) == .mode(.llm))
        #expect(AutomationRoute(url: URL(string: "meraline://mode")!) == .mode(nil))
        #expect(AutomationRoute(url: URL(string: "meraline://mode?agent=maybe")!) == nil)
    }

    @Test func play() {
        #expect(AutomationRoute(url: URL(string: "meraline://play?game=oddOneOut")!) == .play(game: .oddOneOut))
        #expect(AutomationRoute(url: URL(string: "meraline://play?game=rhyme-duel")!) == .play(game: .rhymeDuel))
        #expect(AutomationRoute(url: URL(string: "meraline://play?game=Fix%20the%20Typo")!) == .play(game: .fixTheTypo))
        #expect(AutomationRoute(url: URL(string: "meraline://play?game=letterAuction")!) == .play(game: .longestWord), "a link to the game it replaced")
        #expect(AutomationRoute(url: URL(string: "meraline://play?game=longest-word")!) == .play(game: .longestWord))
        #expect(AutomationRoute(url: URL(string: "meraline://play")!) == .play(game: nil))
        #expect(AutomationRoute(url: URL(string: "meraline://play?game=chess")!) == .play(game: nil))
    }

    @Test func gamesByName() {
        for game in Game.allCases {
            #expect(Game(named: game.rawValue) == game)
            #expect(Game(named: game.title) == game)
            #expect(Game(named: game.title.lowercased().replacingOccurrences(of: " ", with: "_")) == game)
        }
        #expect(Game(named: "") == nil)
        #expect(Game(named: " - ") == nil)
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
