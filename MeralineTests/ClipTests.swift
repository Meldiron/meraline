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
