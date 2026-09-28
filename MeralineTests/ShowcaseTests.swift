import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Meraline

/// The pictures `scripts/showcase.sh` takes (see `Showcase`), one test a scene, each in every appearance asked for.
/// Skipped in every other test run.
///
///   opening       Rhyme Duel waiting for its first move: the invitation card with Random Rhyme
///   longest-word  Longest Word once the model has picked its word: the nine letters in glass bubbles
///   what-changed  a grammar fix of text selected in Mail, showing what it changed
///   usage         Settings › Usage over the last 30 days, from `DemoUsage`
///   usage-games   further down the same page: the games played, and a section for each
///   prompt        Settings › Prompt: the language, and the LLMs' and the agents' instructions
///   prompt-games  further down the same page: the games, one of them changed, and Why?
///   follow-ups    an answer about DNS with three follow-ups under it
///   presets       the presets above an empty chat, Fix Grammar put in the input for a text selected in Mail
///   prompt-presets  Settings › Prompt › Presets: the four defaults and one of your own
///   software-update  Settings › Software Update on a beta: its channel chip and the switch for beta updates
///   cost-nudge    the empty panel with what LLMs and agents have cost today, each past its daily nudge
///   preview       Agent mode: a page and a Markdown file an agent handed over, each with its preview strip
///   note-stack    three answers torn off into one note: the last in front, the edges of the other two under it
@MainActor
@Suite(.serialized, .enabled(if: Showcase.output != nil, "scripts/showcase.sh takes these pictures"))
struct ShowcaseTests {
    @Test func opening() async throws {
        guard Showcase.wants("opening") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage)
            scene.session.startGame(.rhymeDuel)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "opening")
            stage.close(scene.panel)
        }
    }

    @Test func longestWord() async throws {
        guard Showcase.wants("longest-word") else { return }
        // Letters with a good long word in them, drawn as the game draws them, and a word of the model's to hide.
        let seed: UInt64 = 2026
        var preview = GameDice(seed: seed)
        let letters = LongestWord.draw(dice: &preview, in: .english)
        let words = WordCheck.longestWords(from: letters)
        let modelWord = words.dropFirst().first ?? words.first ?? LongestWord.noWord
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, replies: [modelWord.uppercased()])
            scene.session.dice = GameDice(seed: seed)
            scene.session.startGame(.longestWord)
            await GameTestSupport.settle(scene.session)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "longest-word")
            stage.close(scene.panel)
        }
    }

    @Test func whatChanged() async throws {
        guard Showcase.wants("what-changed") else { return }
        let email = "Hi Anna, thank you for you're email. I has attached the report you asked for, its a bit longer then last time. Let me know if their are any questions."
        let fixed = "Hi Anna, thank you for your email. I have attached the report you asked for; it's a bit longer than last time. Let me know if there are any questions."
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, replies: [fixed])
            // The window opens on an empty panel, and then the question goes, as when you ask one.
            await Showcase.settle(1)
            scene.session.bring(try #require(SelectedText(email, appName: "Mail", appURL: URL(fileURLWithPath: "/System/Applications/Mail.app"))))
            scene.session.draft = "Fix the grammar"
            scene.session.send()
            await GameTestSupport.settle(scene.session)
            await scene.session.changesSearch?.value
            let turn = try #require(scene.session.turns.first)
            scene.controller.layout.toggleChanges(of: turn.id)
            await Showcase.settle(2)
            try await stage.capturePanel(scene.panel, as: "what-changed")
            stage.close(scene.panel)
        }
    }

    @Test func usage() async throws {
        guard Showcase.wants("usage") || Showcase.wants("usage-games") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            try await Self.settings(on: stage, pane: .usage, fill: { DemoUsage.fill($0.usage) }) { window in
                // The last 30 days, past the pane's header: the tiles and the chart. Then on to the games.
                Self.select("Month", in: window)
                await Showcase.settle(1)
                Self.scroll(window, to: 170)
                if Showcase.wants("usage") { try await stage.captureWindow(window, as: "usage") }
                Self.scroll(window, to: 2_010)
                if Showcase.wants("usage-games") { try await stage.captureWindow(window, as: "usage-games") }
            }
            stage.close()
        }
    }

    @Test func prompt() async throws {
        guard Showcase.wants("prompt") || Showcase.wants("prompt-games") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let changed = ["systemPrompt.wordFootball": "You are playing Word Football in Czech. Every word must be a real Czech word."]
            try await Self.settings(on: stage, pane: .prompt, defaults: changed) { window in
                Self.scroll(window, to: 170)
                if Showcase.wants("prompt") { try await stage.captureWindow(window, as: "prompt") }
                // Past the presets too.
                Self.scroll(window, to: 1_187)
                if Showcase.wants("prompt-games") { try await stage.captureWindow(window, as: "prompt-games") }
            }
            stage.close()
        }
    }

    @Test func softwareUpdate() async throws {
        guard Showcase.wants("software-update") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let updater = { (preferences: Preferences, defaults: UserDefaults) in
                let updater = Updater(preferences: preferences, defaults: defaults, currentVersion: "1.8.0-beta.1")
                updater.pretendAvailable(lastCheck: .now.addingTimeInterval(-2 * 3_600))
                return updater
            }
            try await Self.settings(on: stage, pane: .softwareUpdate, defaults: ["updateChannel": "beta"], updater: updater) { window in
                try await stage.captureWindow(window, as: "software-update")
            }
            stage.close()
        }
    }

    @Test func presets() async throws {
        guard Showcase.wants("presets") else { return }
        let presets = PromptPreset.defaults(in: .english)
        let text = "hi all, their going to move the launch meeting to thursday because the the slides isnt ready yet, sorry for the late notice"
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage)
            scene.session.bring(try #require(SelectedText(text, appName: "Mail", appURL: URL(fileURLWithPath: "/System/Applications/Mail.app"))))
            scene.session.apply(presets[0], among: presets, sending: false)
            await Showcase.settle(1.5)
            // With the keyboard, as after a click: the cursor after the preset, not all of it selected.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            PromptPresets.moveCursorToEnd(in: scene.panel)
            try await stage.capturePanel(scene.panel, as: "presets")
            stage.close(scene.panel)
        }
    }

    @Test func promptPresets() async throws {
        guard Showcase.wants("prompt-presets") else { return }
        var presets = PromptPreset.defaults(in: .english)
        presets.append(PromptPreset(id: "eli5", title: "Explain Simply", symbol: "lightbulb", text: "Explain this as you would to a curious twelve-year-old, in a short paragraph:"))
        let changed = [PromptPreset.key: try JSONEncoder().encode(presets)]
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            try await Self.settings(on: stage, pane: .prompt, defaults: changed) { window in
                Self.scroll(window, to: 835)
                try await stage.captureWindow(window, as: "prompt-presets")
            }
            stage.close()
        }
    }

    @Test func preview() async throws {
        guard Showcase.wants("preview") else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "MeralineShowcase-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.agentPanel(on: stage, workspaces: root) { request in
                AsyncThrowingStream { continuation in
                    if let workspace = request.workspace {
                        try? Data(ShowcaseFiles.page.utf8).write(to: workspace.appending(path: "release-notes.html"))
                        try? Data(ShowcaseFiles.notes.utf8).write(to: workspace.appending(path: "release-notes.md"))
                        continuation.yield(.activity(.presenting))
                        continuation.yield(.presented(["release-notes.html", "release-notes.md"]))
                    }
                    continuation.yield(.text("Here's the page for the website, and the same notes in Markdown for the GitHub release."))
                    continuation.finish()
                }
            }
            await GameTestSupport.play("Turn the release notes into a page for the website, and keep a Markdown copy for GitHub.", in: scene.session)
            // The stage's windows sit behind every other, where WebKit counts them hidden and draws no page, so
            // the page's web view is told to draw anyway once it is there.
            var webViews: [WKWebView] = []
            for _ in 0..<100 where webViews.isEmpty {
                await Showcase.settle(0.1)
                webViews = scene.panel.contentView?.showcaseDescendants(of: WKWebView.self) ?? []
            }
            let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
            if let method = class_getInstanceMethod(WKWebView.self, occlusion) {
                typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
                let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
                for view in webViews { setter(view, occlusion, false) }
            }
            await Showcase.settle(2)
            try await stage.capturePanel(scene.panel, as: "preview")
            stage.close(scene.panel)
        }
    }

    @Test func followUps() async throws {
        guard Showcase.wants("follow-ups") else { return }
        let answer = """
        DNS, the Domain Name System, turns names like example.com into the IP addresses computers use to reach \
        each other.

        When you open a site, your Mac asks a **resolver**, usually your router or your internet provider. The \
        resolver asks the **root servers** where .com lives, then the **.com servers** where example.com lives, and \
        last the domain's own **authoritative server** for its address. It keeps the answer for the record's \
        **TTL**, so the next visit skips the whole trip.
        """
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, replies: [answer])
            // As the on-device model suggested them for this answer.
            scene.session.followUpSuggester = { _ in
                ["Who runs the root servers?", "How long does a TTL usually last?", "Can I use a faster resolver?"]
            }
            scene.session.draft = "What is DNS?"
            scene.session.send()
            await GameTestSupport.settle(scene.session)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "follow-ups")
            stage.close(scene.panel)
        }
    }

    @Test func costNudge() async throws {
        guard Showcase.wants("cost-nudge") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, defaults: ["costNudge.llm": 1.0, "costNudge.agent": 10.0])
            // A busy day, past the amounts set for both.
            scene.session.usage.record {
                $0.count(answer: TokenUsage(input: 48_000, output: 9_000, cost: 1.42), reported: true, for: "anthropic/claude-sonnet-5")
                $0.count(answer: TokenUsage(input: 910_000, output: 41_000, cost: 12.8), reported: true, for: "claudeCode")
            }
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "cost-nudge")
            stage.close(scene.panel)
        }
    }

    @Test func noteStack() async throws {
        guard Showcase.wants("note-stack") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let notes = AnswerNotes()
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            for (question, answer) in Self.tornOff {
                notes.open(answer: answer, question: question, level: ShowcaseStage.desktop, at: stage.topLeft)
                await Showcase.settle(0.5)
            }
            let window = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) })
            stage.place(window)
            await Showcase.settle(1)
            try await stage.capturePanel(window, as: "note-stack")
            notes.closeAll()
            stage.close()
        }
    }

    /// Three answers torn off into a note, the last on top.
    private static let tornOff = [
        ("180 °C in Fahrenheit?", "**356 °F.** Multiply by 9, divide by 5, and add 32."),
        ("Which folders take the most space here?", "```sh\ndu -sh * | sort -rh | head -10\n```\nThe ten largest, biggest first."),
        ("How long do I boil an egg?", """
            Lower the eggs into water that is already boiling, then:

            - **Runny yolk:** 6 minutes
            - **Jammy:** 7 minutes
            - **Firm:** 10 minutes

            Cool them in ice water for a minute, and they peel easily.
            """),
    ]

    // MARK: Scenes

    private struct PanelScene {
        let session: ChatSession
        let panel: NSWindow
        let controller: PanelController
        let model: ScriptedModel
    }

    /// Preferences as the screenshots have them: Anthropic ready, the window pinned, in a throwaway suite with
    /// `values` in it and no Keychain.
    private static func preferences(_ values: [String: Any] = [:]) -> (Preferences, UserDefaults) {
        let suite = "MeralineShowcase.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: ShortcutSetup.chosenKey)
        for (key, value) in values { defaults.set(value, forKey: key) }
        let preferences = Preferences(defaults: defaults, secrets: SecretStore(read: { _ in "demo" }, write: { _, _ in }), onDeviceModelAvailable: false)
        var anthropic = preferences[.anthropic]
        anthropic.model = "claude-sonnet-5"
        anthropic.apiKey = "demo"
        anthropic.isEnabled = true
        preferences[.anthropic] = anthropic
        preferences.setDefaultProvider(.anthropic, for: .llm)
        preferences.isPinned = true
        return (preferences, defaults)
    }

    /// The real panel on the stage, answering from `replies`, with `values` in its preferences.
    private static func panel(on stage: ShowcaseStage, replies: [String] = [], defaults values: [String: Any] = [:]) throws -> PanelScene {
        let (preferences, defaults) = preferences(values)
        let model = ScriptedModel(replies)
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        return try place(session, preferences: preferences, defaults: defaults, model: model, on: stage)
    }

    /// The real panel on the stage in Agent mode, Claude Code answering through `stream` in a workspace under `root`.
    private static func agentPanel(
        on stage: ShowcaseStage, workspaces root: URL,
        stream: @escaping @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error>
    ) throws -> PanelScene {
        let (preferences, defaults) = preferences()
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.setDefaultProvider(.claudeCode, for: .agent)
        preferences.mode = .agent
        let session = ChatSession(preferences: preferences, workspaceRoot: root, usage: UsageLedger(file: nil), stream: stream)
        return try place(session, preferences: preferences, defaults: defaults, model: ScriptedModel(), on: stage)
    }

    private static func place(
        _ session: ChatSession, preferences: Preferences, defaults: UserDefaults, model: ScriptedModel, on stage: ShowcaseStage
    ) throws -> PanelScene {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: Updater(preferences: preferences, defaults: defaults), updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        let panel = try #require(NSApp.windows.first { $0 is FloatingPanel && !before.contains(ObjectIdentifier($0)) })
        stage.place(panel)
        return PanelScene(session: session, panel: panel, controller: controller, model: model)
    }

    /// The real Settings window on the stage, open on `pane`, for `body` to set up and capture. The window saves
    /// its frame under the app's own name, and the test host is the app, so the frame saved there is put back.
    private static func settings(
        on stage: ShowcaseStage, pane: SettingsPane, defaults values: [String: Any] = [:],
        fill: (ChatSession) -> Void = { _ in },
        updater makeUpdater: (Preferences, UserDefaults) -> Updater = { Updater(preferences: $0, defaults: $1) },
        _ body: (NSWindow) async throws -> Void
    ) async throws {
        let frameKey = "NSWindow Frame MeralineSettings"
        let savedFrame = UserDefaults.standard.object(forKey: frameKey)
        defer { UserDefaults.standard.set(savedFrame, forKey: frameKey) }
        let (preferences, defaults) = preferences(values)
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { _ in AsyncThrowingStream { $0.finish() } }
        fill(session)
        let controller = SettingsWindowController(preferences: preferences, updater: makeUpdater(preferences, defaults), session: session)
        let window = try #require(controller.window)
        window.setFrameAutosaveName("")
        controller.navigation.selection = pane
        stage.place(window)
        await Showcase.settle(1.5)
        try await body(window)
        window.orderOut(nil)
    }

    // MARK: Moving around a pane

    /// Scrolls the pane, the widest scroll view in the window, so `y` points of its content are above its top.
    private static func scroll(_ window: NSWindow, to y: CGFloat) {
        let scrollViews = window.contentView?.showcaseDescendants(of: NSScrollView.self) ?? []
        guard let scrollView = scrollViews.max(by: { $0.frame.width < $1.frame.width }), let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let top = -scrollView.contentInsets.top
        let bottom = document.frame.height - clip.bounds.height + scrollView.contentInsets.bottom
        let offset = min(max(top, top + y), max(top, bottom))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: document.isFlipped ? offset : document.frame.height - clip.bounds.height - offset))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Picks the segment called `label` of the first segmented control that has one, as a click would.
    private static func select(_ label: String, in window: NSWindow) {
        let controls = window.contentView?.showcaseDescendants(of: NSSegmentedControl.self) ?? []
        for control in controls {
            guard let segment = (0..<control.segmentCount).first(where: { control.label(forSegment: $0) == label }) else { continue }
            control.selectedSegment = segment
            control.sendAction(control.action, to: control.target)
            return
        }
    }
}
