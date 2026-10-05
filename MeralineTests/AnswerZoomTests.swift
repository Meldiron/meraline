import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import Meraline

@MainActor
struct AnswerZoomTests {
    private typealias Support = GameTestSupport

    // MARK: Steps

    @Test func stepsGoUpAndDownFromActualSize() {
        let larger = AnswerZoom.actualSize.applying(.zoomIn)
        #expect(larger.scale == 1.15)
        #expect(larger.percent == "115%")
        let smallest = larger.applying(.zoomOut).applying(.zoomOut)
        #expect(smallest.scale == 0.85)
        #expect(!smallest.allows(.zoomOut))
        #expect(smallest.applying(.zoomOut) == smallest)
        #expect(smallest.applying(.actualSize) == .actualSize)
        #expect(!AnswerZoom.actualSize.allows(.actualSize))
    }

    @Test func zoomStopsAtTheLargestStep() {
        let largest = AnswerZoom.steps.reduce(AnswerZoom.actualSize) { zoom, _ in zoom.applying(.zoomIn) }
        #expect(largest.scale == 3)
        #expect(largest.percent == "300%")
        #expect(!largest.allows(.zoomIn))
        #expect(AnswerZoom(scale: 12).scale == 3)
        #expect(AnswerZoom(scale: 0.1).scale == 0.85)
    }

    @Test func aStepFromWhereAPinchLeftItGoesToTheNextOne() {
        let pinched = AnswerZoom(scale: 1.4)
        #expect(pinched.applying(.zoomIn).scale == 1.5)
        #expect(pinched.applying(.zoomOut).scale == 1.3)
    }

    // MARK: Pinching

    @Test func aPinchZoomsSmoothlyAndSettlesWhenItEnds() {
        var zoom = AnswerZoom.actualSize
        for _ in 0..<10 { zoom = zoom.pinched(by: 0.02) }
        #expect(zoom.scale > 1.21 && zoom.scale < 1.23, "each event grows it a little: \(zoom.scale)")
        // Between two steps, it keeps a whole percent.
        #expect(zoom.pinched(by: 0, ending: true).scale == 1.22)
        // Near a step, it settles on the step, 100% most of all.
        #expect(zoom.pinched(by: 0.06, ending: true).scale == 1.3)
        #expect(AnswerZoom(scale: 1.03).pinched(by: 0, ending: true) == .actualSize)
        #expect(AnswerZoom(scale: 2.9).pinched(by: 0.5, ending: true).scale == 3, "never past the largest step")
    }

    // MARK: Shortcuts

    private func step(_ keyCode: Int, _ characters: String, _ modifiers: ActionShortcut.Modifiers) -> AnswerZoom.Step? {
        AnswerZoom.Step(keyCode: UInt16(keyCode), characters: characters, modifiers: modifiers)
    }

    @Test func commandPlusMinusAndZeroZoom() {
        // + takes Shift on a US keyboard, and ⌘= means the same, as in Safari.
        #expect(step(kVK_ANSI_Equal, "=", .command) == .zoomIn)
        #expect(step(kVK_ANSI_Equal, "+", [.command, .shift]) == .zoomIn)
        // A Czech keyboard has a key of its own for +.
        #expect(step(kVK_ANSI_1, "+", .command) == .zoomIn)
        #expect(step(kVK_ANSI_KeypadPlus, "+", .command) == .zoomIn)
        #expect(step(kVK_ANSI_Minus, "-", .command) == .zoomOut)
        #expect(step(kVK_ANSI_KeypadMinus, "-", .command) == .zoomOut)
        #expect(step(kVK_ANSI_0, "0", .command) == .actualSize)

        #expect(step(kVK_ANSI_Equal, "=", []) == nil)
        #expect(step(kVK_ANSI_Equal, "=", [.command, .option]) == nil)
        #expect(step(kVK_ANSI_Minus, "_", [.command, .shift]) == nil)
        #expect(step(kVK_ANSI_0, ")", [.command, .shift]) == nil)
    }

    @Test func commandZeroGoesByTheKeysPlaceWhateverTheLayoutTypesThere() {
        #expect(step(kVK_ANSI_0, "é", .command) == .actualSize, "the key where a Czech keyboard types é, and 0 only with Shift")
        #expect(step(kVK_ANSI_0, "à", .command) == .actualSize, "and where a French one types à")
        #expect(step(kVK_ANSI_Keypad0, "0", .command) == .actualSize)
        #expect(step(kVK_ANSI_0, "0", [.command, .shift]) == nil, "⇧⌘ and the key isn't ⌘0, though it types 0 there")
        #expect(step(kVK_ANSI_0, "é", []) == nil)
        #expect(step(kVK_ANSI_9, "0", .command) == nil, "a 0 typed by another key isn't the key")
    }

    @Test func theKeycapsSayPlusAndMinus() {
        #expect(AnswerZoom.Step.zoomIn.shortcut.keycaps == ["⌘", "+"])
        #expect(AnswerZoom.Step.zoomOut.shortcut.keycaps == ["⌘", "−"])
        #expect(AnswerZoom.Step.actualSize.shortcut.text == "⌘0")
    }

    // MARK: The chat's actions

    private func context(_ session: ChatSession, layout: PanelLayout = PanelLayout()) -> PanelContext {
        PanelContext(session: session, preferences: Support.preferences(), layout: layout, openSettings: { _ in })
    }

    @Test func commandPlusZoomsTheAnswersAndCommandZeroGoesBack() async throws {
        let session = Support.session(ScriptedModel(["Big words for the back of the room."]))
        await Support.play("Read it from afar", in: session)
        let layout = PanelLayout()
        let context = context(session, layout: layout)
        #expect(context.canZoomAnswers)
        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_0), characters: "0", modifiers: .command) == nil, "already at actual size")

        let zoomIn = try #require(context.action(forKeyCode: UInt16(kVK_ANSI_Equal), characters: "=", modifiers: .command))
        #expect(zoomIn.id == "zoomIn")
        context.run(zoomIn, in: .chat, fromShortcut: true)
        #expect(layout.answerZoom.scale == 1.15)

        let actualSize = try #require(context.action(forKeyCode: UInt16(kVK_ANSI_0), characters: "0", modifiers: .command))
        #expect(actualSize.subtitle == "Answers are at 115%")
        #expect(context.chatMenu?.filtered(by: "bigger").flatMap(\.actions).map(\.id) == ["zoomIn"])
        context.run(actualSize, in: .chat, fromShortcut: true)
        #expect(layout.answerZoom == .actualSize)

        // On a Czech keyboard the 0 key types é, and the chat's shortcut still finds Actual Size.
        layout.zoomAnswers(.zoomIn)
        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_0), characters: "é", modifiers: .command)?.id == "actualSize")
        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_0), characters: "0", modifiers: [.command, .shift]) == nil)
    }

    @Test func theLargestZoomOffersNoZoomIn() async {
        let session = Support.session(ScriptedModel(["Huge."]))
        await Support.play("How big?", in: session)
        let layout = PanelLayout()
        layout.answerZoom = AnswerZoom(scale: 3)
        let ids = context(session, layout: layout).chatMenu?.actions.map(\.id) ?? []
        #expect(!ids.contains("zoomIn"))
        #expect(ids.contains("zoomOut"))
        #expect(ids.contains("actualSize"))
    }

    @Test func gamesHaveNoAnswersToZoom() async {
        let session = Support.session(ScriptedModel(["OK: apple"]))
        session.startGame(.wordFootball)
        await Support.play("banana", in: session)
        let context = context(session)
        #expect(!context.canZoomAnswers)
        #expect(context.action(forKeyCode: UInt16(kVK_ANSI_Equal), characters: "=", modifiers: .command) == nil)
    }

    // MARK: Drawing

    @Test func zoomedMarkdownTakesMoreRoom() {
        let markdown = "# Steps\n\nPreheat the oven.\n\n- Mix\n- Bake\n\n```sh\nmake bread\n```"
        func size(_ zoom: CGFloat) -> NSSize {
            NSHostingView(rootView: MarkdownView(markdown: markdown).environment(\.answerZoom, zoom).frame(width: 400)).fittingSize
        }
        let actual = size(1)
        let doubled = size(2)
        #expect(actual.height > 0)
        #expect(doubled.height > actual.height * 1.5, "\(actual.height) → \(doubled.height)")
    }
}
