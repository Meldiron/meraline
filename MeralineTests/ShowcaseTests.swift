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
///   usage-kinds   the same page counting the agents alone: the LLMs' and the decisions' tiles faded, left out
///   prompt        Settings › Prompt: the language, and the LLMs' and the agents' instructions
///   prompt-games  further down the same page: the games, one of them changed, and Why?
///   follow-ups    an answer about DNS with three follow-ups under it
///   presets       the presets above an empty chat, Fix Grammar put in the input for a text selected in Mail
///   prompt-presets  Settings › Prompt › Presets: the four defaults and one of your own
///   preset-editor  Settings › Prompt with Urgent? open in its sheet
///   preset-icons  the same sheet with its icons searched for “urgent”
///   software-update  Settings › Software Update on a beta: its channel chip and the switch for beta updates
///   cost-nudge    the empty panel with what LLMs and agents have cost today
///   preview       Agent mode: a page and a Markdown file an agent handed over, each with its preview strip
///   note-stack    three answers torn off into one note: the last in front, the edges of the other two under it
///   colon-card    "Fix the grammar:" typed in the input, and the Context card it opened, holding the text
///   decision      Decision mode: Jev's Yes about a text selected in Mail, with how sure it is
///   decision-levels  Decision mode: a priority placed along Low, Medium, and High, and the answers under the input
///   decision-lines  Decision mode about each line: six tasks from Notes grouped under Yes, No, and Not sure
///   decision-scope  Decision mode: the switch under the input set to each line, and the note that says what it decides about
///   decision-live  Decision mode: the Context card deciding as you type, a question kept from the input, the input's, and three presets answered on glass capsules
///   decision-answers  Decision mode: the answers' panel open over the capsule under the input, Yes / No and two lists of your own, the levels in use selected with Edit and Remove
///   decision-answers-form  the same panel's form editing the levels: the toggle between a set and levels in order, and Save and Use
///   preset-decisions  every preset of Decision mode asked at once about a text from Mail, each answer on one card
///   decision-improve  Decision mode with Live on, after a click on Improve: the edited text, the capsules answered under it, and the note of what changed, with Undo
///   new-chat-draft  the clock's panel with Stash Draft and New Chat at its top while the Context card holds text and no chat is open
///   table-fit     a three-column table wrapped to the card, and beside a capture of 1.12.0 as table-fit-before-after
///   undo-rewrite  the chat's actions searched for "undo" after Make Shorter: Undo Rewrite
///   try-again     an answer cut off by its connection, the banner's Try Again, and Ask Again first in the footer
///   agent-question  Agent mode: Claude Code's question with its two choices wearing ⌘1 and ⌘2
///   shake-undo    the empty panel right after a shake, the clock's capsule pink and saying Undo
///   streaming-scrolled  a long answer still coming, scrolled up to its start, with Stop in the footer
///   rich-copy     what a rich-text app pastes from Copy Answer, the Markdown before and the formatted text after
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
                if Showcase.wants("usage") {
                    try await stage.captureWindow(window, as: "usage")
                    // Further down, the chart alone, beside a capture of 1.12.0, whose chart labeled every bar and cut
                    // its hover numbers off.
                    Self.scroll(window, to: 500)
                    await Showcase.settle(0.5)
                    try await stage.captureWindow(window, as: "usage-chart")
                    try stage.compose(before: "usage-before", after: "usage-chart", as: "usage-before-after")
                    Self.scroll(window, to: 170)
                }
                Self.scroll(window, to: 2_404)
                if Showcase.wants("usage-games") { try await stage.captureWindow(window, as: "usage-games") }
            }
            stage.close()
        }
    }

    @Test func usageKinds() async throws {
        guard Showcase.wants("usage-kinds") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            try await Self.settings(on: stage, pane: .usage, defaults: ["usage.kinds": ["agent"]], fill: { DemoUsage.fill($0.usage) }) { window in
                Self.select("Month", in: window)
                await Showcase.settle(1)
                Self.scroll(window, to: 170)
                try await stage.captureWindow(window, as: "usage-kinds")
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

    @Test func decisionModels() async throws {
        guard Showcase.wants("decision-models") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            // Settings › Decision Models on Ollama's pane, turned on with Nimble, as after "ollama pull nimble".
            let defaults: [String: Any] = ["ollamaDecision.enabled": true, "ollamaDecision.model": "nimble"]
            try await Self.settings(on: stage, pane: .provider(.ollamaDecision), defaults: defaults) { window in
                // The sidebar down to its Decision Models group, so TypeSafe and OpenRouter show beside the chosen Ollama.
                Self.scroll(window, to: 1_000, sidebar: true)
                await Showcase.settle(0.5)
                try await stage.captureWindow(window, as: "decision-models")
            }
            stage.close()
        }
    }

    @Test func ollaya() async throws {
        guard Showcase.wants("ollaya") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            // Settings › Decision Models on Ollaya's pane, turned on with Kev's smallest size, as after "ollaya pull kev:0.8b".
            let defaults: [String: Any] = ["ollaya.enabled": true, "ollaya.model": "kev:0.8b"]
            // With no key: the scenes' secret store answers every provider, and Ollaya's key is for a server that asks.
            try await Self.settings(on: stage, pane: .provider(.ollaya), defaults: defaults, prepare: { preferences in
                var ollaya = preferences[.ollaya]
                ollaya.apiKey = ""
                preferences[.ollaya] = ollaya
            }) { window in
                // The sidebar down to its Decision Models group, so the other three show beside the chosen Ollaya.
                Self.scroll(window, to: 1_000, sidebar: true)
                await Showcase.settle(0.5)
                try await stage.captureWindow(window, as: "ollaya")
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
            // As after a Shift-click: with the text to work on there, a click would ask at once.
            scene.session.prepare(presets[0], among: presets)
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

    /// How far Settings › Prompt scrolls for the LLMs' presets at the top.
    private static let presetsScroll: CGFloat = 1_085

    @Test func promptPresets() async throws {
        guard Showcase.wants("prompt-presets") else { return }
        var presets = PromptPreset.defaults(in: .english)
        presets.append(PromptPreset(id: "eli5", title: "Explain Simply", symbol: "lightbulb", text: "Explain this as you would to a curious twelve-year-old, in a short paragraph."))
        let changed = [PromptPreset.key: try JSONEncoder().encode(presets)]
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            try await Self.settings(on: stage, pane: .prompt, defaults: changed) { window in
                await Self.scrollGradually(window, to: Self.presetsScroll)
                try await stage.captureWindow(window, as: "prompt-presets")
            }
            stage.close()
        }
    }

    /// Decision mode's Urgent? open in its editor, and, for `preset-icons`, the icons it can take searched for
    /// “urgent”, a word Apple's keywords don't know.
    @Test func presetEditor() async throws {
        for (name, query) in [("preset-editor", nil), ("preset-icons", "urgent")] where Showcase.wants(name) {
            for appearance in Showcase.appearances {
                let stage = ShowcaseStage(appearance)
                try await Self.settings(on: stage, pane: .prompt) { window in
                    await Self.scrollGradually(window, to: Self.presetsScroll)
                    let editor = PresetEditor(
                        kind: .decision, preset: PromptPreset.decisionDefaults[0], isNew: false, comesBack: true,
                        choosingIcon: query != nil, iconQuery: query ?? ""
                    ) { _ in } delete: {}
                    let sheet = NSWindow(contentViewController: NSHostingController(rootView: editor))
                    sheet.appearance = appearance.appearance
                    window.beginSheet(sheet) { _ in }
                    await Showcase.settle(1.5)
                    // The sheet and the popover stay behind every other app, as the stage's windows do.
                    let popovers = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
                    for extra in [sheet] + popovers { extra.level = ShowcaseStage.desktop }
                    try await stage.captureWindows([window, sheet] + popovers, as: name)
                    for popover in popovers { popover.orderOut(nil) }
                    window.endSheet(sheet)
                }
                stage.close()
            }
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

    @Test func decision() async throws {
        guard Showcase.wants("decision") else { return }
        let text = "hi all, can we move the launch meeting to thursday? the slides aren't ready and legal still has to sign off on the pricing page, sorry for the late notice"
        let decision = Decision(options: [.init(label: "Yes", probability: 0.91), .init(label: "No", probability: 0.09)], isYesNo: true, confidence: 0.82)
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage, decisions: [decision])
            scene.session.bring(try #require(SelectedText(text, appName: "Mail", appURL: URL(fileURLWithPath: "/System/Applications/Mail.app"))))
            scene.session.draft = "Is this urgent?"
            scene.session.send()
            await GameTestSupport.settle(scene.session)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "decision")
            stage.close(scene.panel)
        }
    }

    /// Every preset of Decision mode asked at once from the circle at the end of their row, each answer on one card.
    @Test func presetDecisions() async throws {
        guard Showcase.wants("preset-decisions") else { return }
        let text = "hi all, can we move the launch meeting to thursday? the slides aren't ready and legal still has to sign off on the pricing page, sorry for the late notice"
        let yes = Decision(options: [.init(label: "Yes", probability: 0.86), .init(label: "No", probability: 0.14)], isYesNo: true, confidence: 0.72)
        let no = Decision(options: [.init(label: "Yes", probability: 0.04), .init(label: "No", probability: 0.96)], isYesNo: true, confidence: 0.92)
        let neutral = Decision(options: [.init(label: "Friendly", probability: 0.31), .init(label: "Neutral", probability: 0.63), .init(label: "Angry", probability: 0.06)], confidence: 0.7)
        let high = Decision(options: [.init(label: "Low", probability: 0.08), .init(label: "Medium", probability: 0.34), .init(label: "High", probability: 0.58)], isOrdered: true, score: 1.5, confidence: 0.55)
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage, decisions: [yes, no, neutral, high])
            scene.session.bring(try #require(SelectedText(text, appName: "Mail", appURL: URL(fileURLWithPath: "/System/Applications/Mail.app"))))
            scene.session.askPresets(PromptPreset.decisionDefaults)
            await GameTestSupport.settle(scene.session)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "preset-decisions")
            stage.close(scene.panel)
        }
    }

    @Test func decisionLevels() async throws {
        guard Showcase.wants("decision-levels") else { return }
        let text = "Checkout has been failing for every customer in Europe since 9:40, and the payment provider's status page says nothing. Support has 40 tickets already."
        let decision = Decision(
            options: [.init(label: "Low", probability: 0.02), .init(label: "Medium", probability: 0.14), .init(label: "High", probability: 0.84)],
            isOrdered: true, score: 1.82, confidence: 0.76
        )
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage, decisions: [decision])
            scene.session.bring(try #require(SelectedText(text, appName: "Slack", appURL: URL(fileURLWithPath: "/Applications/Slack.app"))))
            scene.session.draft = "How high a priority is this? Low < Medium < High"
            scene.session.send()
            await GameTestSupport.settle(scene.session)
            // The next question, typed but not asked, so the answers under the input show what it picks from.
            scene.session.draft = "Should we page the on-call engineer? Now / After lunch / Tomorrow"
            await Showcase.settle(1.5)
            // With the keyboard, as after typing: the cursor after the question, not all of it selected.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            PromptPresets.moveCursorToEnd(in: scene.panel)
            try await stage.capturePanel(scene.panel, as: "decision-levels")
            stage.close(scene.panel)
        }
    }

    @Test func decisionLines() async throws {
        guard Showcase.wants("decision-lines") else { return }
        let lines = [
            "Renew the office lease before Friday", "Order more coffee for the kitchen", "Reply to legal about the pricing page",
            "Book the team dinner for next month", "Fix the checkout bug for European customers", "Update the on-call schedule",
        ]
        func yes(_ p: Double) -> Decision { Decision(options: [.init(label: "Yes", probability: p), .init(label: "No", probability: 1 - p)], isYesNo: true, confidence: abs(2 * p - 1)) }
        let batch = DecisionBatch(scope: .lines, answers: .yesNo, total: lines.count, items: zip(lines, [0.92, 0.06, 0.86, 0.11, 0.97, 0.58]).enumerated().map { index, pair in
            DecisionBatch.Item(id: index, text: pair.0, decision: yes(pair.1))
        })
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage, batches: [batch], scope: .lines)
            scene.session.bring(try #require(SelectedText(lines.joined(separator: "\n"), appName: "Notes", appURL: URL(fileURLWithPath: "/System/Applications/Notes.app"))))
            scene.session.draft = "Is this urgent?"
            scene.session.send()
            await GameTestSupport.settle(scene.session)
            // Yes open on its three tasks, No and Not sure folded to their headers.
            let turn = try #require(scene.session.turns.last)
            let yes = try #require(batch.groups(unsureBelow: Decision.defaultUnsureBelow).first)
            scene.controller.layout.toggleDecisionGroup(yes.id, of: turn.id)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "decision-lines")
            stage.close(scene.panel)
        }
    }

    @Test func decisionScope() async throws {
        guard Showcase.wants("decision-scope") else { return }
        let lines = [
            "Renew the office lease before Friday", "Order more coffee for the kitchen", "Reply to legal about the pricing page",
            "Book the team dinner for next month", "Fix the checkout bug for European customers", "Update the on-call schedule",
        ]
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage)
            scene.session.bring(try #require(SelectedText(lines.joined(separator: "\n"), appName: "Notes", appURL: URL(fileURLWithPath: "/System/Applications/Notes.app"))))
            scene.session.draft = "Is this urgent?"
            // As when Each Line is clicked: the note under the text says what the switch decides about.
            scene.session.chooseScope(.lines)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "decision-scope")
            stage.close(scene.panel)
        }
    }

    /// The answers' panel over the capsule under the input, with levels of your own in use, then its form.
    @Test func decisionAnswers() async throws {
        let wantsList = Showcase.wants("decision-answers")
        let wantsForm = Showcase.wants("decision-answers-form")
        guard wantsList || wantsForm else { return }
        let text = "Checkout has been failing for every customer in Europe since 9:40, and the payment provider's status page says nothing."
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage, answers: ["Billing / Technical / Sales", "Low < Medium < High"])
            scene.session.bring(try #require(SelectedText(text, appName: "Slack", appURL: URL(fileURLWithPath: "/Applications/Slack.app"))))
            scene.session.draft = "How high a priority is this?"
            // Lower on the stage, so the panel opens upward over the card, as it does on a screen with room.
            let room: CGFloat = 320
            scene.panel.setFrameTopLeftPoint(NSPoint(x: stage.topLeft.x, y: stage.topLeft.y - room))
            await Showcase.settle(0.5)
            scene.controller.layout.actionPanel = ActionPanelRequest(kind: .answers)
            await Showcase.settle(1)
            if wantsList {
                try await stage.capturePanel(scene.panel, as: "decision-answers", roomAbove: room)
            }
            if wantsForm {
                scene.controller.layout.actionPanel = ActionPanelRequest(kind: .answers, editing: "answers.own.1.edit")
                await Showcase.settle(1)
                // With the keyboard, so the field shows its cursor after the levels.
                await Showcase.waitForIdle()
                scene.panel.makeKey()
                await Showcase.settle(0.5)
                try await stage.capturePanel(scene.panel, as: "decision-answers-form", roomAbove: room)
            }
            stage.close(scene.panel)
        }
    }

    @Test func decisionLive() async throws {
        guard Showcase.wants("decision-live") else { return }
        func yes(_ p: Double) -> Decision { Decision(options: [.init(label: "Yes", probability: p), .init(label: "No", probability: 1 - p)], isYesNo: true, confidence: abs(2 * p - 1)) }
        // What each question is answered with, by its wording: the input's, and the presets turned on.
        let answers: [String: Decision] = [
            "Is this ready to send?": yes(0.88),
            "Does it name a deadline?": yes(0.12),
            "Is this urgent?": yes(0.94),
            "What is the tone of this text?": Decision(options: [.init(label: "Friendly", probability: 0.22), .init(label: "Neutral", probability: 0.71), .init(label: "Angry", probability: 0.07)], confidence: 0.7),
            "How high a priority is this?": Decision(options: [.init(label: "Low", probability: 0.04), .init(label: "Medium", probability: 0.2), .init(label: "High", probability: 0.76)], isOrdered: true, score: 1.72, confidence: 0.76),
        ]
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage, live: answers, presets: ["urgent", "tone", "priority"])
            // A question kept from the input with the plus on its capsule, beside the presets.
            scene.session.liveDecisions.keep("Does it name a deadline?")
            scene.session.draft = "Is this ready to send?"
            await Showcase.settle(1.0)
            // With the keyboard in the card, as while the text is being typed and the capsules answer under it.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            scene.session.writeState()
            scene.controller.layout.stateFocusRequest += 1
            scene.session.typedState = "Hi team, checkout has been down for European customers since 9:40 and payments fail with a 502. I’m on it, but we may need to pause the campaign until it’s fixed."
            await Showcase.settle(1.5)
            #expect(Self.moveCursorToEnd(ofCardIn: scene.panel), "the card has the keyboard")
            try await stage.capturePanel(scene.panel, as: "decision-live")
            stage.close(scene.panel)
        }
    }

    /// Improve on the Context card: the text after one click, the capsules answered under it, and the note of
    /// what it changed, with Undo. Anthropic edits the text, as the LLMs' default, and the live decisions answer
    /// by each question's wording.
    @Test func decisionImprove() async throws {
        guard Showcase.wants("decision-improve") else { return }
        func yes(_ p: Double) -> Decision { Decision(options: [.init(label: "Yes", probability: p), .init(label: "No", probability: 1 - p)], isYesNo: true, confidence: abs(2 * p - 1)) }
        let answers: [String: Decision] = [
            "Is this ready to send?": yes(0.93),
            "Is this urgent?": yes(0.96),
            "How high a priority is this?": Decision(options: [.init(label: "Low", probability: 0.03), .init(label: "Medium", probability: 0.11), .init(label: "High", probability: 0.86)], isOrdered: true, score: 1.83, confidence: 0.86),
        ]
        let before = "Hi team, checkout has been down for European customers since 9:40 and payments fail with a 502. I’m on it, but we may need to pause the campaign until it’s fixed."
        let after = "Hi team, checkout has been down for every European customer since 9:40 and all payments fail with a 502. I’m on it now; please pause the campaign until it’s fixed, and I’ll report back by noon."
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.decisionPanel(on: stage, replies: [after], live: answers, presets: ["urgent", "priority"])
            scene.session.draft = "Is this ready to send?"
            await Showcase.settle(1.0)
            // With the keyboard in the card, as after a click on Improve while writing there.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            scene.session.writeState()
            scene.controller.layout.stateFocusRequest += 1
            scene.session.typedState = before
            await Showcase.settle(1.5)
            scene.session.improveContext()
            var waited = 0
            while scene.session.isImprovingContext, waited < 200 {
                try await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            #expect(scene.session.improvementNote?.hasPrefix("Improved") == true, "the text was improved: \(scene.session.improvementNote ?? "no note")")
            await Showcase.settle(1.5)
            #expect(Self.moveCursorToEnd(ofCardIn: scene.panel), "the card has the keyboard")
            try await stage.capturePanel(scene.panel, as: "decision-improve")
            stage.close(scene.panel)
        }
    }

    /// ⌘N with no chat open: the clock's panel with Stash Draft and New Chat at its top while the Context card
    /// holds text, above a chat kept in Recent Chats.
    @Test func newChatDraft() async throws {
        guard Showcase.wants("new-chat-draft") else { return }
        let text = "Hi team, checkout has been down for European customers since 9:40 and payments fail with a 502. I’m on it, but we may need to pause the campaign until it’s fixed."
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, replies: ["A CRDT is a data structure that several replicas can change at once and still agree on, without a server deciding the order."])
            scene.session.draft = "What’s a CRDT, in one sentence?"
            scene.session.send()
            await GameTestSupport.settle(scene.session)
            _ = scene.session.reset()
            scene.session.writeState()
            scene.session.typedState = text
            // Lower on the stage, so the panel opens upward over the card, as it does on a screen with room.
            let room: CGFloat = 320
            scene.panel.setFrameTopLeftPoint(NSPoint(x: stage.topLeft.x, y: stage.topLeft.y - room))
            await Showcase.settle(0.5)
            scene.controller.layout.actionPanel = ActionPanelRequest(kind: .history)
            await Showcase.settle(1)
            try await stage.capturePanel(scene.panel, as: "new-chat-draft", roomAbove: room)
            stage.close(scene.panel)
        }
    }

    @Test func costNudge() async throws {
        guard Showcase.wants("cost-nudge") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage)
            // A busy day.
            scene.session.usage.record {
                $0.count(answer: TokenUsage(input: 48_000, output: 9_000, cost: 1.42), reported: true, for: "anthropic/claude-sonnet-5")
                $0.count(answer: TokenUsage(input: 910_000, output: 41_000, cost: 12.8), reported: true, for: "claudeCode")
            }
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "cost-nudge")
            stage.close(scene.panel)
        }
    }

    @Test func addText() async throws {
        guard Showcase.wants("add-text") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage)
            scene.session.draft = "Draft a friendly reply saying Thursday at 3 works"
            await Showcase.settle(1.0)
            // With the keyboard, as when Tab is pressed: it opens the note card and gives it the keyboard, for a
            // piece of context written by hand, alongside the question.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            scene.session.writeState()
            scene.controller.layout.stateFocusRequest += 1
            scene.session.typedState = "Hi — any chance you're free this week to go over the Q3 numbers? Tuesday or Thursday afternoon both work for me. — Sam"
            await Showcase.settle(1.5)
            #expect(Self.moveCursorToEnd(ofCardIn: scene.panel), "the card has the keyboard")
            try await stage.capturePanel(scene.panel, as: "add-text")
            stage.close(scene.panel)
        }
    }

    @Test func presetText() async throws {
        guard Showcase.wants("preset-text") else { return }
        let presets = PromptPreset.defaults(in: .english)
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage)
            await Showcase.settle(1.0)
            // With the keyboard, as when Fix Grammar is clicked with nothing to work on yet: the card opens for
            // the text and takes the keyboard, and the text is pasted in.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            if scene.session.apply(presets[0], among: presets) { scene.controller.layout.stateFocusRequest += 1 }
            scene.session.typedState = "hi all, their going to move the launch meeting to thursday because the the slides isnt ready yet, sorry for the late notice"
            await Showcase.settle(1.5)
            #expect(Self.moveCursorToEnd(ofCardIn: scene.panel), "the card has the keyboard")
            try await stage.capturePanel(scene.panel, as: "preset-text")
            stage.close(scene.panel)
        }
    }

    /// Puts the cursor after the text of the card for context written by hand, when it has the keyboard, so the
    /// picture shows the card as it is after typing; whether it had it. Otherwise the input has the keyboard, with
    /// its text all selected, which the picture shows too.
    @discardableResult
    private static func moveCursorToEnd(ofCardIn window: NSWindow) -> Bool {
        guard let editor = window.firstResponder as? NSTextView, !editor.isFieldEditor else { return false }
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.setSelectedRange(end)
        return true
    }

    @Test func colonCard() async throws {
        guard Showcase.wants("colon-card") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage)
            // With the keyboard, as while it is typed: the colon at the end of the question opens the Context card
            // by itself, the cursor stays in the input, and the text to work on goes on the card.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            scene.session.draft = "Fix the grammar:"
            #expect(scene.session.typedState == "", "the colon opened the card")
            scene.session.typedState = "Me and him was going to the store tomorow, but their not open on sundays."
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "colon-card")
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

    @Test func tableFit() async throws {
        guard Showcase.wants("table-fit") else { return }
        let answer = """
        | | Cortado | Latte |
        | --- | --- | --- |
        | **Espresso** | 1 shot | 1-2 shots |
        | **Milk** | Small amount, steamed (not foamy) | Large amount, steamed with a layer of foam |
        | **Milk:Espresso Ratio** | ~1:1 | ~3:1 or more |
        | **Volume** | ~4 oz (small) | ~8-12 oz (larger) |
        | **Texture** | Smooth, less foam | Creamy, with foam layer |
        | **Flavor** | Stronger coffee taste | Milkier, softer coffee taste |
        """
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, replies: [answer])
            scene.session.followUpSuggester = { _ in ["How much milk in a cortado?", "What is a cappuccino?", "How does temperature affect taste?"] }
            await GameTestSupport.play("What is the difference between a cortado and a latte? Give me a small table.", in: scene.session)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "table-fit")
            // Beside a capture of 1.12.0, where the same table scrolled sideways with its last column cut off.
            try stage.compose(before: "table-fit-before", after: "table-fit", as: "table-fit-before-after")
            stage.close(scene.panel)
        }
    }

    @Test func undoRewrite() async throws {
        guard Showcase.wants("undo-rewrite") else { return }
        let answer = """
        DNS, the Domain Name System, turns names like example.com into the IP addresses computers use to reach \
        each other. Your Mac asks a resolver, which asks the root servers, the .com servers, and last the domain's \
        own server, and keeps the answer for a while so the next visit skips the trip.
        """
        let shorter = "DNS turns names like example.com into the IP addresses computers use to reach each other."
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, replies: [answer, shorter])
            scene.session.followUpSuggester = { _ in [] }
            await GameTestSupport.play("What is DNS?", in: scene.session)
            scene.session.rewrite(.shorter)
            await GameTestSupport.settle(scene.session)
            // Lower on the stage, so the chat's panel opens upward over the answer, as it does on a screen with room.
            let room: CGFloat = 360
            scene.panel.setFrameTopLeftPoint(NSPoint(x: stage.topLeft.x, y: stage.topLeft.y - room))
            await Showcase.settle(0.5)
            scene.controller.layout.actionPanel = ActionPanelRequest(kind: .chat)
            await Showcase.settle(1)
            // "undo" typed into the panel's search, in the test host alone.
            await Showcase.waitForIdle()
            scene.panel.makeKey()
            await Showcase.settle(0.3)
            for character in "undo" { Self.press(character, in: scene.panel) }
            await Showcase.settle(1)
            try await stage.capturePanel(scene.panel, as: "undo-rewrite", roomAbove: room)
            stage.close(scene.panel)
        }
    }

    @Test func tryAgain() async throws {
        guard Showcase.wants("try-again") else { return }
        let partial = "A cortado is espresso cut with about the same amount of warm milk, so it stays strong and short. A latte uses far more steamed milk and a layer of foam, which makes it"
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage) { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.text(partial))
                    continuation.finish(throwing: LLMError.interrupted)
                }
            }
            await GameTestSupport.play("How is a cortado different from a latte?", in: scene.session)
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "try-again")
            stage.close(scene.panel)
        }
    }

    @Test func agentQuestion() async throws {
        guard Showcase.wants("agent-question") else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "MeralineShowcase-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let question = AgentPrompt.Question(
            header: "Release", text: "Which release is this changelog entry for?",
            options: [.init(label: "1.3.0", detail: "New features, nothing breaks"), .init(label: "2.0.0", detail: "Includes breaking changes")]
        )
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.agentPanel(on: stage, workspaces: root) { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.activity(.thinking))
                    continuation.yield(.prompt(AgentPrompt(id: "req-1", kind: .question([question])), AgentPromptResponder { _ in }))
                }
            }
            scene.session.draft = "Draft a changelog entry for the next release."
            scene.session.send()
            for _ in 0..<100 where scene.session.turns.last?.pendingPrompt == nil { await Showcase.settle(0.1) }
            await Showcase.settle(1.5)
            try await stage.capturePanel(scene.panel, as: "agent-question")
            stage.close(scene.panel)
        }
    }

    @Test func shakeUndo() async throws {
        guard Showcase.wants("shake-undo") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage, replies: ["Paris.", "Berlin.", "Madrid."])
            for question in ["What is the capital of France?", "And of Germany?", "Spain?"] {
                await GameTestSupport.play(question, in: scene.session)
                scene.session.reset()
            }
            await Showcase.settle(1)
            // The capsule says Undo for five seconds from the shake, so the shake is noted again once the Mac has
            // been still for the capture's own wait, and the capture follows at once.
            scene.session.shakeUndoWindow = .seconds(600)
            let forgot = scene.session.shakeAwayHistory()
            await Showcase.waitForIdle(6)
            scene.controller.layout.noteForgotten(forgot)
            await Showcase.settle(0.8)
            try await stage.capturePanel(scene.panel, as: "shake-undo")
            stage.close(scene.panel)
        }
    }

    @Test func streamingScrolled() async throws {
        guard Showcase.wants("streaming-scrolled") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try Self.panel(on: stage) { _ in
                // An answer that keeps coming, a step every second or so, until the scene closes.
                AsyncThrowingStream { continuation in
                    let task = Task {
                        for (index, step) in Self.resolutionSteps.enumerated() {
                            try Task.checkCancellation()
                            continuation.yield(.text((index == 0 ? "" : "\n\n") + step))
                            try await Task.sleep(for: .seconds(0.7))
                        }
                        try await Task.sleep(for: .seconds(600))
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
            scene.session.draft = "Explain how DNS resolution works, step by step."
            scene.session.send()
            await Showcase.settle(9)
            // The reader scrolls back up to the start while the rest still comes.
            let conversation = try #require(scene.panel.contentView?.showcaseDescendants(of: NSScrollView.self).first {
                ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 40
            })
            try Self.wheel(conversation, by: 4_000)
            await Showcase.settle(1)
            try await stage.capturePanel(scene.panel, as: "streaming-scrolled")
            scene.session.stop()
            stage.close(scene.panel)
        }
    }

    /// A long answer, a step at a time.
    private static let resolutionSteps = [
        "**1. Your Mac checks its own cache.** Every answer it has looked up lately is kept for the record's TTL, so a site you visited a minute ago needs no lookup at all.",
        "**2. It asks the resolver.** Usually your router or your internet provider, set by DHCP. The resolver keeps a cache of its own, shared by everyone who uses it.",
        "**3. The resolver asks a root server.** There are thirteen named root servers, mirrored hundreds of times over. A root server doesn't know example.com, but it knows who runs .com.",
        "**4. It asks the .com servers.** They know which name servers are authoritative for example.com, and hand those back.",
        "**5. It asks example.com's own servers.** These hold the actual records: the A record with the IPv4 address, the AAAA record with the IPv6 one, MX records for mail, and so on.",
        "**6. The answer travels back** to the resolver, which caches it, and to your Mac, which caches it too and opens the connection.",
        "**7. The TTL decides how long it lasts.** A short TTL, say sixty seconds, lets a site move quickly; a long one, a day, saves lookups.",
        "**8. DNSSEC can sign each step,** so a resolver can check that nobody changed the answer on the way.",
        "**9. Encrypted DNS** (DNS over HTTPS or TLS) hides the questions from anyone watching the network, though the resolver still sees them.",
        "**10. When something goes wrong,** the resolver answers NXDOMAIN for a name that doesn't exist, or SERVFAIL when it couldn't get an answer at all.",
        "**11. Your Mac keeps its own list too:** /etc/hosts is read before any of this, which is how a name can be pointed at a test server.",
        "**12. To see it happen,** run `dig example.com` in Terminal: the answer section has the records, and the last lines say which server answered and how long it took.",
    ]

    @Test func richCopy() async throws {
        guard Showcase.wants("rich-copy") else { return }
        let answer = """
        A **cortado** is espresso cut with about the same amount of warm milk. Compared with a latte:

        - **Milk:** about 1:1, with no foam
        - **Size:** 120 ml, against 240 ml and up
        - **Taste:** the coffee comes through

        | Drink | Milk | Foam |
        | --- | --- | --- |
        | Cortado | a little | none |
        | Latte | a lot | a layer |
        """
        for appearance in Showcase.appearances {
            try ShowcaseStage(appearance).composePaste(of: answer, as: "rich-copy")
        }
    }

    /// Types `character` into `window`'s first responder, in the test host alone: an event made here and sent to
    /// the window, never the keyboard.
    private static func press(_ character: Character, in window: NSWindow) {
        let text = String(character)
        guard let down = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0
        ) else { return }
        window.sendEvent(down)
    }

    /// Turns the scroll wheel over `scroll`, as a reader does: up for a positive `distance`, in points.
    private static func wheel(_ scroll: NSScrollView, by distance: Int32) throws {
        var left = distance
        while left != 0 {
            let step = max(-80, min(80, left))
            let turn = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try #require(NSEvent(cgEvent: turn)))
            left -= step
        }
    }

    // MARK: Scenes

    struct PanelScene {
        let session: ChatSession
        let panel: NSWindow
        let controller: PanelController
        let model: ScriptedModel
    }

    /// Preferences as the screenshots have them: Anthropic ready, the window pinned, in a throwaway suite with
    /// `values` in it and no Keychain.
    static func preferences(_ values: [String: Any] = [:]) -> (Preferences, UserDefaults) {
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

    /// The real panel on the stage, answering from `replies`.
    static func panel(on stage: ShowcaseStage, replies: [String] = []) throws -> PanelScene {
        let (preferences, defaults) = preferences()
        let model = ScriptedModel(replies)
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        return try place(session, preferences: preferences, defaults: defaults, model: model, on: stage)
    }

    /// The real panel on the stage, answering through `stream`, for an answer that comes as a model's does.
    static func panel(on stage: ShowcaseStage, stream: @escaping @MainActor (ChatRequest) -> AsyncThrowingStream<StreamOutput, Error>) throws -> PanelScene {
        let (preferences, defaults) = preferences()
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: stream)
        return try place(session, preferences: preferences, defaults: defaults, model: ScriptedModel(), on: stage)
    }

    /// The real panel on the stage in Decision mode, TypeSafe answering with `decisions`, or with `batches` about
    /// each word or line of the `scope`, and, with `live`, deciding as you type on the Context card, each question
    /// answered by its wording, with `presets` turned on; the LLMs' default, Anthropic, answers from `replies`, for Improve.
    private static func decisionPanel(
        on stage: ShowcaseStage, replies: [String] = [], decisions: [Decision] = [], batches: [DecisionBatch] = [], scope: DecisionScope = .whole,
        answers: [String] = [], live: [String: Decision]? = nil, presets: Set<String> = []
    ) throws -> PanelScene {
        let (preferences, defaults) = preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "demo", isEnabled: true)
        preferences.setDefaultProvider(.typeSafe, for: .decision)
        preferences.mode = .decision
        preferences.decisionScope = scope
        // Lists of your own, the last in use.
        for list in answers { preferences.addOwnAnswers(list) }
        let model = ScriptedModel(replies, decisions: decisions, batches: batches)
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { model.stream($0) }) { questions, _, _, _ in
            var decisions: [String: Decision] = [:]
            for question in questions { decisions[question.id] = live?[question.question] }
            return DecisionClient.LiveReply(decisions: decisions, usage: .zero)
        }
        if live != nil {
            session.liveDecisions.isOn = true
            session.liveDecisions.enabledPresets = presets
        }
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

    static func place(
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
        // Placed, not shown through `show()`, so the content is told it is up, or it stays faded out.
        controller.layout.isShown = true
        stage.place(panel)
        return PanelScene(session: session, panel: panel, controller: controller, model: model)
    }

    /// The real Settings window on the stage, open on `pane`, for `body` to set up and capture. The window saves
    /// its frame under the app's own name, and the test host is the app, so the frame saved there is put back.
    private static func settings(
        on stage: ShowcaseStage, pane: SettingsPane, defaults values: [String: Any] = [:],
        prepare: (Preferences) -> Void = { _ in },
        fill: (ChatSession) -> Void = { _ in },
        updater makeUpdater: (Preferences, UserDefaults) -> Updater = { Updater(preferences: $0, defaults: $1) },
        _ body: (NSWindow) async throws -> Void
    ) async throws {
        let frameKey = "NSWindow Frame MeralineSettings"
        let savedFrame = UserDefaults.standard.object(forKey: frameKey)
        defer { UserDefaults.standard.set(savedFrame, forKey: frameKey) }
        let (preferences, defaults) = preferences(values)
        prepare(preferences)
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

    /// Scrolls the pane, the widest scroll view in the window, or with `sidebar` the list of panes, the one around a
    /// table, so `y` points of its content are above its top.
    private static func scroll(_ window: NSWindow, to y: CGFloat, sidebar: Bool = false) {
        let scrollViews = window.contentView?.showcaseDescendants(of: NSScrollView.self) ?? []
        let chosen = sidebar
            ? scrollViews.first { $0.documentView is NSTableView }
            : scrollViews.max(by: { $0.frame.width < $1.frame.width })
        guard let scrollView = chosen, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let top = -scrollView.contentInsets.top
        let bottom = document.frame.height - clip.bounds.height + scrollView.contentInsets.bottom
        let offset = min(max(top, top + y), max(top, bottom))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: document.isFlipped ? offset : document.frame.height - clip.bounds.height - offset))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Scrolls the pane to `y` a step at a time, as a hand would, so a lazy form lays out each part it passes:
    /// one jump down Settings › Prompt left sections drawn where others had been.
    private static func scrollGradually(_ window: NSWindow, to y: CGFloat) async {
        for step in stride(from: 0, to: y, by: 120) {
            scroll(window, to: step)
            await Showcase.settle(0.05)
        }
        scroll(window, to: y)
        await Showcase.settle(0.5)
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
