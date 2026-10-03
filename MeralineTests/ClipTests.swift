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
///   live          the Live decisions demo for the promo: a reply to Nora typed badly, the capsules turning red, typed
///                 again and turning green as it grows, a question kept with the plus, and Return; over the promo's
///                 night sky at the films' spot with MERALINE_CLIP_BACKDROP (scripts/clips.sh --backdrop)
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

    /// Nora's message, the text every live question is about together with the reply, and the two replies: the
    /// tired one, which the capsules turn red on, and the one typed in its place, which they turn green on as it
    /// grows. Nothing in them is an em dash; people don't type those.
    static let norasMessage = "The deck still has the old pricing. We present at 9. Can this be fixed tonight?"
    static let tiredReply = "It's midnight. The pricing was correct when you approved it. I'll see what I can do."
    static let betterReply = "Thanks for catching it, Nora. I'll swap in the new pricing tonight and send the deck by 7."

    @Test func live() async throws {
        guard Showcase.wantsClip("live") else { return }
        let yes = Decision(options: [.init(label: "Yes", probability: 0.95), .init(label: "No", probability: 0.05)], isYesNo: true, confidence: 0.9)
        let film = Showcase.clipBackdrop != nil
        let stage = ShowcaseStage(.dark, backdropImage: Showcase.clipBackdrop)
        let (preferences, defaults) = ShowcaseTests.preferences()
        preferences[.typeSafe] = ProviderSettings(model: "jev-latest", baseURL: Provider.typeSafe.defaultBaseURL, apiKey: "demo", isEnabled: true)
        preferences.setDefaultProvider(.typeSafe, for: .decision)
        preferences.mode = .decision
        let checks = Checks()
        // Return's decision comes as Jev's does, a third of a second later; the live ones from the text so far.
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil), stream: { _ in
            AsyncThrowingStream { continuation in
                Task {
                    try? await Task.sleep(for: .milliseconds(360))
                    continuation.yield(.decision(yes))
                    continuation.finish()
                }
            }
        }, decideLive: { questions, state, _, _ in
            checks.asked += 1
            try await Task.sleep(for: .milliseconds(320))
            let text = state.map(\.text).last ?? ""
            var decisions: [String: Decision] = [:]
            for question in questions { decisions[question.id] = Self.liveAnswer(to: question.question, about: text) }
            return DecisionClient.LiveReply(decisions: decisions, usage: .zero)
        })
        let scene = try ShowcaseTests.place(session, preferences: preferences, defaults: defaults, model: ScriptedModel(), on: stage)
        // Nora's message, as the film's selection scene hands it over; the panel high, since it grows tall.
        session.bring(try #require(SelectedText(Self.norasMessage, appName: "Messages", appURL: URL(fileURLWithPath: "/System/Applications/Messages.app"))))
        scene.panel.setFrameTopLeftPoint(film ? stage.filmTopLeft(top: 110) : stage.topLeft)
        await Showcase.settle(1)
        try await stage.recordPanel(scene.panel, as: "live", seconds: 36, room: CGSize(width: 0, height: 420), region: film ? ShowcaseStage.filmRegion : nil) { marks in
            let layout = scene.controller.layout
            await Showcase.settle(0.8)
            marks.mark("card")
            session.writeState()
            layout.stateFocusRequest += 1
            await Showcase.settle(0.9)
            marks.mark("live")
            session.toggleLiveDecisions()
            await Showcase.settle(0.7)
            marks.mark("presets")
            session.toggleLivePreset("tone")
            await Showcase.settle(0.35)
            session.toggleLivePreset("urgent")
            await Showcase.settle(0.6)
            marks.mark("question")
            layout.focusRequest += 1
            await Showcase.settle(0.25)
            await Self.type("Ready to send?") { session.draft = $0 }
            await Showcase.settle(0.5)
            marks.mark("draft1")
            layout.stateFocusRequest += 1
            await Showcase.settle(0.25)
            await Self.type(Self.tiredReply) { session.typedState = $0 }
            marks.mark("typed1")
            await Self.settleLive(session)
            marks.mark("red")
            await Showcase.settle(1.6)
            // ⌘A, ⌫.
            marks.mark("clear")
            session.typedState = ""
            await Showcase.settle(0.45)
            marks.mark("draft2")
            await Self.type(Self.betterReply) { session.typedState = $0 }
            marks.mark("typed2")
            await Self.settleLive(session)
            marks.mark("green")
            await Showcase.settle(1.4)
            marks.mark("question2")
            layout.focusRequest += 1
            await Showcase.settle(0.25)
            await Self.type("Does it promise a time?") { session.draft = $0 }
            await Showcase.settle(0.5)
            marks.mark("keep")
            session.keepLiveQuestion()
            await Self.settleLive(session)
            marks.mark("kept")
            await Showcase.settle(1.1)
            // The question that matters, typed once more for the record, and Return.
            marks.mark("question3")
            await Self.type("Ready to send?") { session.draft = $0 }
            await Showcase.settle(0.5)
            marks.mark("enter")
            session.send()
            for _ in 0..<200 {
                guard session.isStreaming else { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            await Showcase.settle(0.15)
            marks.mark("shown")
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

    /// Types `text` a character at a time into `set`, at about a quick typist's pace with a little unevenness, a
    /// breath at spaces and a longer one at the end of a sentence.
    private static func type(_ text: String, into set: @MainActor (String) -> Void) async {
        var typed = ""
        var seed: UInt64 = 7
        for character in text {
            typed.append(character)
            set(typed)
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let jitter = Double((seed >> 33) % 40) / 1_000
            let pause = character == " " ? 0.085 : ".,!?".contains(character) ? 0.17 : 0.046
            try? await Task.sleep(for: .seconds(pause + jitter))
        }
    }

    /// Waits until the live decisions have answered about the text as it is, up to a few seconds.
    private static func settleLive(_ session: ChatSession) async {
        for _ in 0..<150 {
            guard session.liveDecisions.isWorking else { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// What the demo's model decides about the reply so far: the tired reply reads angry and not ready to send, the
    /// better one turns friendly and ready as it grows, both are urgent, and only the better one promises a time.
    /// Written to the words, so each capsule turns on a particular word, not a particular second.
    nonisolated static func liveAnswer(to question: String, about text: String) -> Decision {
        func yesNo(_ yes: Double) -> Decision {
            Decision(options: [.init(label: "Yes", probability: yes), .init(label: "No", probability: 1 - yes)], isYesNo: true, confidence: abs(2 * yes - 1))
        }
        func tone(friendly: Double, neutral: Double, angry: Double, confidence: Double) -> Decision {
            Decision(options: [.init(label: "Friendly", probability: friendly), .init(label: "Neutral", probability: neutral), .init(label: "Angry", probability: angry)], confidence: confidence)
        }
        let has = { (word: String) in text.contains(word) }
        let tired = text.hasPrefix("It") || has("midnight") || has("approved")
        let better = text.hasPrefix("Th") || has("Nora")
        let early = text.count < 10
        switch question {
        case "What is the tone of this text?":
            if early { return tone(friendly: 0.3, neutral: 0.42, angry: 0.28, confidence: 0.14) }
            if tired { return has("approved") ? tone(friendly: 0.04, neutral: 0.1, angry: 0.86, confidence: 0.82) : has("midnight") ? tone(friendly: 0.08, neutral: 0.2, angry: 0.72, confidence: 0.64) : tone(friendly: 0.2, neutral: 0.5, angry: 0.3, confidence: 0.3) }
            if better { return has("tonight") ? tone(friendly: 0.84, neutral: 0.13, angry: 0.03, confidence: 0.79) : has("Nora") ? tone(friendly: 0.7, neutral: 0.26, angry: 0.04, confidence: 0.63) : tone(friendly: 0.36, neutral: 0.58, angry: 0.06, confidence: 0.52) }
            return tone(friendly: 0.33, neutral: 0.44, angry: 0.23, confidence: 0.2)
        case "Ready to send?":
            if early { return yesNo(0.5) }
            if tired { return has("approved") ? yesNo(0.06) : has("midnight") ? yesNo(0.13) : yesNo(0.3) }
            if better { return has("by 7") ? yesNo(0.95) : has("tonight") ? yesNo(0.89) : has("Nora") ? yesNo(0.68) : yesNo(0.56) }
            return yesNo(0.5)
        case "Is this urgent?":
            if early { return yesNo(0.52) }
            return has("tonight") || has("midnight") ? yesNo(0.97) : has("pricing") ? yesNo(0.86) : yesNo(0.72)
        case "Does it promise a time?":
            return has("by 7") ? yesNo(0.96) : yesNo(0.2)
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
