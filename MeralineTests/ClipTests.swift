import AppKit
import SwiftUI
import Testing
@testable import Meraline

/// The clips `scripts/clips.sh` records (see `ShowcaseStage.recordPanel`): the panel's animations, each a few seconds
/// long, to judge a change to one against the version before it. Skipped in every other test run.
///
///   open-close    the window opening on an empty chat and closing again, as ⌥ Space does
///   ask           a question sent: the conversation appears, the answer streams in, the follow-ups come, and Esc starts a new chat
///   what-changed  Show What Changed on a grammar fix, and Show Answer back
///   live          the Live decisions demo for the promo: the window opened, Decision mode, Write It, Live, Urgent?;
///                 a request read red, then green as its ending changes; Flirt? red, Not sure, then green and surer
///                 with every word; four questions at once over an invitation as it is typed; over the promo's night
///                 sky at the films' spot with MERALINE_CLIP_BACKDROP (scripts/clips.sh --backdrop)
@MainActor
@Suite(.serialized, .enabled(if: Showcase.clips != nil, "scripts/clips.sh records these"))
struct ClipTests {
    @Test func openClose() async throws {
        guard Showcase.wantsClip("open-close") else { return }
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try ShowcaseTests.panel(on: stage)
            await Showcase.settle(1)
            scene.controller.close()
            await Showcase.settle(0.5)
            try await stage.recordPanel(scene.panel, as: "open-close", seconds: 4.5) {
                await Showcase.settle(0.6)
                scene.controller.show()
                // Back over the gradient: `show()` places the window as Settings says, before anything is drawn.
                scene.panel.setFrameTopLeftPoint(stage.topLeft)
                await Showcase.settle(2.2)
                scene.controller.close()
                await Showcase.settle(1.2)
            }
            stage.close(scene.panel)
        }
    }

    @Test func ask() async throws {
        guard Showcase.wantsClip("ask") else { return }
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
            // The answer comes a word at a time after a moment's thought, as a model's does.
            let scene = try ShowcaseTests.panel(on: stage) { _ in
                AsyncThrowingStream { continuation in
                    Task {
                        try? await Task.sleep(for: .milliseconds(1_200))
                        for word in answer.split(separator: " ", omittingEmptySubsequences: false) {
                            continuation.yield(.text(String(word) + " "))
                            try? await Task.sleep(for: .milliseconds(24))
                        }
                        continuation.finish()
                    }
                }
            }
            scene.session.followUpSuggester = { _ in
                ["Who runs the root servers?", "How long does a TTL usually last?", "Can I use a faster resolver?"]
            }
            scene.panel.makeKey()
            await Showcase.settle(1)
            try await stage.recordPanel(scene.panel, as: "ask", seconds: 9, room: CGSize(width: 0, height: 480)) {
                scene.session.draft = "What is DNS?"
                await Showcase.settle(0.8)
                scene.session.send()
                await Self.answered(scene.session)
                await Showcase.settle(2)
                scene.session.reset()
                await Showcase.settle(1.5)
            }
            stage.close(scene.panel)
        }
    }

    /// What the demo types: a request that isn't urgent, then its ending cut and a deadline typed in; an ending to
    /// the boss, a wink, and a line that is plainly flirting; and an invitation to a meeting, for four questions at
    /// once. Nothing in them is an em dash; people don't type those.
    static let notUrgent = "Hi Dana, could you take a look at the Q3 deck? No rush, next week is fine."
    static let urgentEnding = " We present at 9 tomorrow, so I need it tonight."
    static let bossEnding = " See you tomorrow, boss."
    static let winkEnding = " wink wink."
    static let flirtEnding = " sexyyy, can't wait to hold you tight."
    static let invitation = "Team, please join the Q3 planning review on Thursday at 10 in the big room."

    /// The Live film's one clip (see the promo project's src/films/live/scenes.ts): the window opens in LLM mode,
    /// switches to Decision, Write It opens the Context card, Live goes on, Urgent? joins; a request that isn't
    /// urgent reads red, its ending is cut and a deadline typed in, and it reads green; Urgent? gives way to Flirt?,
    /// red through "See you tomorrow, boss.", Not sure at a wink, green and surer with every word of a line that
    /// is plainly flirting; then Urgent?, Tone, and Priority join Flirt?, the text is cleared, and an invitation to
    /// a meeting is typed while all four decide as it grows. The decider is written to the words, so a capsule
    /// turns on a particular word, and the whole scene marks its moments for the film's cut.
    @Test func live() async throws {
        guard Showcase.wantsClip("live") else { return }
        let film = Showcase.clipBackdrop != nil
        let stage = ShowcaseStage(.dark, backdropImage: Showcase.clipBackdrop)
        let (preferences, defaults) = ShowcaseTests.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "demo", isEnabled: true)
        preferences.setDefaultProvider(.typeSafe, for: .decision)
        // Flirt? beside the default presets, as the user's own Settings have it.
        preferences[presets: .decision] = PromptPreset.decisionDefaults + [PromptPreset(id: "flirt", title: "Flirt?", symbol: "heart", text: "Is this flirting?")]
        preferences.mode = .llm
        let checks = Checks()
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { _ in
            AsyncThrowingStream { $0.finish() }
        }, decideLive: { questions, state, _, _ in
            checks.asked += 1
            try await Task.sleep(for: .milliseconds(320))
            let text = state.map(\.text).last ?? ""
            var decisions: [String: Decision] = [:]
            for question in questions { decisions[question.id] = Self.liveAnswer(to: question.question, about: text) }
            return DecisionClient.LiveReply(decisions: decisions, usage: .zero)
        })
        let scene = try ShowcaseTests.place(session, preferences: preferences, defaults: defaults, model: ScriptedModel(), on: stage)
        let topLeft = film ? stage.filmTopLeft(top: 110) : stage.topLeft
        scene.panel.setFrameTopLeftPoint(topLeft)
        await Showcase.settle(0.6)
        // Hidden to begin with, so the clip opens with the window coming up, as ⌥ Space brings it.
        scene.controller.close()
        await Showcase.settle(0.5)
        try await stage.recordPanel(scene.panel, as: "live", seconds: 48, room: CGSize(width: 0, height: 420), region: film ? ShowcaseStage.filmRegion : nil) { marks in
            let layout = scene.controller.layout
            await Showcase.settle(0.8)
            marks.mark("open")
            scene.controller.show()
            scene.panel.setFrameTopLeftPoint(topLeft)
            await Showcase.settle(1.3)
            marks.mark("mode") // ⌘3
            preferences.mode = .decision
            await Showcase.settle(1.2)
            marks.mark("writeIt")
            session.writeState()
            layout.stateFocusRequest += 1
            await Showcase.settle(1.0)
            marks.mark("live")
            session.toggleLiveDecisions()
            await Showcase.settle(0.8)
            marks.mark("urgent")
            session.toggleLivePreset("urgent")
            await Showcase.settle(0.8)
            marks.mark("draft1")
            await Self.type(Self.notUrgent, into: session)
            marks.mark("typed1")
            await Self.settleLive(session)
            marks.mark("red1")
            await Showcase.settle(1.5)
            marks.mark("cut1") // ⌥⌫ six times: "No rush, next week is fine." goes.
            await Self.erase(words: 6, from: session)
            await Self.settleLive(session)
            await Showcase.settle(0.7)
            marks.mark("draft1b")
            await Self.type(Self.urgentEnding, into: session)
            marks.mark("typed1b")
            await Self.settleLive(session)
            marks.mark("green1")
            await Showcase.settle(1.7)
            marks.mark("swap")
            session.toggleLivePreset("urgent")
            await Showcase.settle(0.45)
            marks.mark("flirt")
            session.toggleLivePreset("flirt")
            await Self.settleLive(session)
            marks.mark("red2")
            await Showcase.settle(1.4)
            marks.mark("draft2")
            await Self.type(Self.bossEnding, into: session)
            marks.mark("typed2")
            await Self.settleLive(session)
            marks.mark("red3")
            await Showcase.settle(1.4)
            marks.mark("cut2") // "boss." goes, "wink wink." comes.
            await Self.erase(words: 1, from: session)
            await Self.type(Self.winkEnding, into: session)
            marks.mark("typed3")
            await Self.settleLive(session)
            marks.mark("unsure")
            await Showcase.settle(1.5)
            marks.mark("cut3") // "wink wink." goes, and the line that leaves no doubt comes.
            await Self.erase(words: 2, from: session)
            await Self.type(Self.flirtEnding, into: session)
            marks.mark("typed4")
            await Self.settleLive(session)
            marks.mark("green2")
            await Showcase.settle(2.2)
            marks.mark("presets")
            session.toggleLivePreset("urgent")
            await Showcase.settle(0.3)
            session.toggleLivePreset("tone")
            await Showcase.settle(0.3)
            session.toggleLivePreset("priority")
            await Showcase.settle(0.7)
            marks.mark("clear") // ⌘A ⌫
            session.typedState = ""
            await Showcase.settle(0.6)
            marks.mark("draft3")
            await Self.type(Self.invitation, into: session)
            marks.mark("typed5")
            await Self.settleLive(session)
            marks.mark("done")
            marks.count("checks", checks.asked)
            await Showcase.settle(2.5)
        }
        stage.close(scene.panel)
    }

    /// How many times the live decisions asked, for the film's count.
    @MainActor
    private final class Checks {
        var asked = 0
    }

    /// Types `text` a character at a time after what the card has, at about a quick typist's pace with a little
    /// unevenness, a breath at spaces and a longer one at the end of a sentence.
    private static func type(_ text: String, into session: ChatSession) async {
        var typed = session.typedState ?? ""
        var seed: UInt64 = 7
        for character in text {
            typed.append(character)
            session.typedState = typed
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let jitter = Double((seed >> 33) % 40) / 1_000
            let pause = character == " " ? 0.085 : ".,!?".contains(character) ? 0.17 : 0.046
            try? await Task.sleep(for: .seconds(pause + jitter))
        }
    }

    /// Takes the last `words` words off the card, one at a time, as ⌥⌫ does.
    private static func erase(words: Int, from session: ChatSession) async {
        for _ in 0..<words {
            var text = (session.typedState ?? "").trimmingCharacters(in: .whitespaces)
            while let last = text.last, !last.isWhitespace { text.removeLast() }
            session.typedState = text.trimmingCharacters(in: .whitespaces)
            try? await Task.sleep(for: .milliseconds(70))
        }
    }

    /// Waits until the live decisions have answered about the text as it is, up to a few seconds.
    private static func settleLive(_ session: ChatSession) async {
        for _ in 0..<150 {
            guard session.liveDecisions.isWorking else { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// What the demo's model decides about the text so far, written to the words so each capsule turns on a
    /// particular one: "no rush" isn't urgent and "tonight" is; "boss" isn't flirting, a wink might be, and the
    /// last line leaves no doubt, surer with every word; and the invitation reads as not urgent, neutral in tone,
    /// and a high priority once the room is named.
    nonisolated static func liveAnswer(to question: String, about text: String) -> Decision {
        func yesNo(_ yes: Double) -> Decision {
            Decision(options: [.init(label: "Yes", probability: yes), .init(label: "No", probability: 1 - yes)], isYesNo: true, confidence: abs(2 * yes - 1))
        }
        func tone(_ friendly: Double, _ neutral: Double, _ angry: Double, confidence: Double) -> Decision {
            Decision(options: [.init(label: "Friendly", probability: friendly), .init(label: "Neutral", probability: neutral), .init(label: "Angry", probability: angry)], confidence: confidence)
        }
        func priority(_ low: Double, _ medium: Double, _ high: Double, score: Double, confidence: Double) -> Decision {
            Decision(options: [.init(label: "Low", probability: low), .init(label: "Medium", probability: medium), .init(label: "High", probability: high)], isOrdered: true, score: score, confidence: confidence)
        }
        let has = { (words: String) in text.range(of: words, options: .caseInsensitive) != nil }
        let early = text.count < 12
        switch question {
        case "Is this urgent?":
            if early { return yesNo(0.5) }
            if has("tonight") { return yesNo(0.96) }
            if has("tomorrow") { return yesNo(0.9) }
            if has("no rush") || has("next week") { return yesNo(0.08) }
            if has("big room") { return yesNo(0.11) }
            if has("Thursday") { return yesNo(0.19) }
            if has("planning") { return yesNo(0.31) }
            return yesNo(0.45)
        case "Is this flirting?":
            if has("hold you tight") { return yesNo(0.999) }
            if has("wait") { return yesNo(0.94) }
            if has("sexy") { return yesNo(0.86) }
            if has("wink") { return yesNo(0.6) }
            if has("boss") { return yesNo(0.1) }
            if early { return yesNo(0.5) }
            return yesNo(0.07)
        case "What is the tone of this text?":
            if early { return tone(0.3, 0.42, 0.28, confidence: 0.14) }
            if has("big room") { return tone(0.22, 0.7, 0.08, confidence: 0.66) }
            if has("Thursday") { return tone(0.4, 0.52, 0.08, confidence: 0.5) }
            if has("join") { return tone(0.56, 0.38, 0.06, confidence: 0.52) }
            return tone(0.3, 0.55, 0.15, confidence: 0.4)
        case "How high a priority is this?":
            if early { return priority(0.3, 0.4, 0.3, score: 1, confidence: 0.1) }
            if has("big room") { return priority(0.06, 0.18, 0.76, score: 1.7, confidence: 0.76) }
            if has("Q3") { return priority(0.1, 0.35, 0.55, score: 1.45, confidence: 0.55) }
            if has("planning") { return priority(0.15, 0.6, 0.25, score: 1.1, confidence: 0.6) }
            return priority(0.3, 0.45, 0.25, score: 0.95, confidence: 0.3)
        default:
            return yesNo(0.5)
        }
    }

    @Test func whatChanged() async throws {
        guard Showcase.wantsClip("what-changed") else { return }
        let email = "Hi Anna, thank you for you're email. I has attached the report you asked for, its a bit longer then last time. Let me know if their are any questions."
        let fixed = "Hi Anna, thank you for your email. I have attached the report you asked for; it's a bit longer than last time. Let me know if there are any questions."
        for appearance in Showcase.appearances {
            let stage = ShowcaseStage(appearance)
            let scene = try ShowcaseTests.panel(on: stage, replies: [fixed])
            scene.panel.makeKey()
            await Showcase.settle(0.8)
            scene.session.bring(try #require(SelectedText(email, appName: "Mail", appURL: URL(fileURLWithPath: "/System/Applications/Mail.app"))))
            scene.session.draft = "Fix the grammar"
            scene.session.send()
            await Self.answered(scene.session)
            await scene.session.changesSearch?.value
            let turn = try #require(scene.session.turns.first)
            await Showcase.settle(1.5)
            try await stage.recordPanel(scene.panel, as: "what-changed", seconds: 5, room: CGSize(width: 0, height: 120)) {
                await Showcase.settle(0.6)
                scene.controller.layout.toggleChanges(of: turn.id)
                await Showcase.settle(2)
                scene.controller.layout.toggleChanges(of: turn.id)
                await Showcase.settle(1.6)
            }
            stage.close(scene.panel)
        }
    }

    /// Waits for the answer to end.
    private static func answered(_ session: ChatSession) async {
        while session.isStreaming { try? await Task.sleep(for: .milliseconds(50)) }
    }
}
