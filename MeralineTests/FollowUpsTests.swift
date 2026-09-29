import AppKit
import Foundation
import Synchronization
import Testing
@testable import Meraline

@MainActor
struct FollowUpsTests {
    private typealias Support = GameTestSupport

    private func drawn(_ question: String, _ answer: String, asked: [String] = [], language: AnswerLanguage = .english) -> [String] {
        FollowUps.drawn(for: FollowUps.Request(question: question, answer: answer, asked: asked, language: language))
    }

    /// Waits until the follow-ups for the last answer have been worked out.
    private func settleFollowUps(_ session: ChatSession) async {
        for _ in 0..<1_000 {
            guard session.followUps.isEmpty else { return }
            await Task.yield()
        }
    }

    // MARK: Drawn from the answer

    @Test func aTermInBoldGetsATellMeMoreWithItsArticle() {
        let answer = """
        DNS turns names like example.com into the addresses computers use. Your Mac asks a **resolver**, which asks \
        the **root servers**, then the domain's own **authoritative server**, and caches the answer for its **TTL**.
        """
        #expect(drawn("What is DNS?", answer) == ["Tell me more about the resolver", "Can you give me an example?", "Why does it matter?"])
    }

    @Test func labelsInBoldAndTermsTheQuestionNamesAreNoTerms() {
        let answer = """
        **Note:** **DNS** is how names become addresses. **Step 2** is where the **cache** comes in, and it keeps \
        each answer for a while so the next lookup is quick and nothing has to be asked twice over the network.
        """
        let suggestions = drawn("What is DNS?", answer)
        #expect(suggestions.first == "Tell me more about the cache")
        #expect(FollowUps.isTerm("Obsidian", after: "best notes app"))
        #expect(!FollowUps.isTerm("Pros", after: ""))
        #expect(!FollowUps.isTerm("Option 3", after: ""))
        #expect(!FollowUps.isTerm("DNS", after: "What is dns?"))
        #expect(!FollowUps.isTerm("a whole sentence set in bold for emphasis", after: ""))
    }

    @Test func codeComesFirst() {
        let answer = """
        Use a `task(id:)` that sleeps before searching, so each keystroke cancels the search before it:

        ```swift
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            await search(query)
        }
        ```
        """
        #expect(drawn("How do I debounce a search field in SwiftUI?", answer) == [
            "Walk me through this code", "How would I test this?", "What are common mistakes to avoid?",
        ])
    }

    @Test func aChoiceComparesTheFirstTwoThingsListed() {
        let answer = """
        1. **Obsidian** — local Markdown files, plugins, and a graph of your notes.
        2. **Apple Notes** — free, syncs over iCloud, and good enough for most people.
        3. **Bear** — a beautiful Markdown editor with tags.
        """
        #expect(drawn("best note taking apps for mac", answer) == [
            "How do Obsidian and Apple Notes compare?", "Tell me more about Bear", "Which would you pick, and why?",
        ])
    }

    @Test func aShortAnswerIsAskedToGoOn() {
        #expect(drawn("capital of australia", "Canberra.") == ["Tell me more", "Why is that?"])
    }

    @Test func eachKindOfQuestionHasItsOwnSuggestions() {
        #expect(FollowUps.Kind(of: "translate good morning to Japanese") == .translation)
        #expect(FollowUps.Kind(of: "Why is the sky blue?") == .why)
        #expect(FollowUps.Kind(of: "how do I undo a commit") == .howTo)
        #expect(FollowUps.Kind(of: "How does TCP work?") == .explain)
        #expect(FollowUps.Kind(of: "Postgres vs SQLite for a small app") == .choice)
        #expect(FollowUps.Kind(of: "Should I learn Rust") == .choice)
        #expect(FollowUps.Kind(of: "Make a script that renames the photos") == .task)
        #expect(FollowUps.Kind(of: "a haiku about autumn") == .other)
        #expect(FollowUps.Kind(of: "") == .other)
        let kinds: [FollowUps.Kind] = [.howTo, .task, .choice, .why, .explain, .translation, .other]
        for kind in kinds {
            #expect(kind.suggestions.count == FollowUps.minimum)
            #expect(kind.suggestions.allSatisfy { $0.count <= 40 })
        }
    }

    @Test func neverAQuestionTheChatHasAsked() {
        let answer = "**Rayleigh scattering**: the air scatters short blue waves of sunlight far more than the long red ones, so blue light reaches your eyes from every part of the sky at once."
        #expect(drawn("Why is the sky blue?", answer, asked: ["Can you give me an example?"]) == [
            "Tell me more about Rayleigh scattering", "What are the exceptions?",
        ])
        #expect(drawn("Why is the sky blue?", "Rayleigh scattering.", asked: ["Tell me more"]).isEmpty, "one left isn't worth showing")
    }

    @Test func noneInAnotherLanguage() {
        let czech = "DNS převádí jména jako example.cz na IP adresy. Počítač se ptá **resolveru**, ten se ptá kořenových serverů a odpověď si uloží do mezipaměti na dobu, kterou určuje TTL."
        #expect(drawn("Co je DNS?", czech).isEmpty)
        #expect(drawn("What is DNS?", "DNS turns names into addresses, which your computer then uses to reach the server that hosts a site.", language: .czech).isEmpty)
        #expect(FollowUps.isEnglish("Canberra."))
    }

    // MARK: Cleaning

    @Test func suggestionsAreCleanedUp() {
        let request = FollowUps.Request(question: "What is DNS?", answer: "")
        #expect(FollowUps.cleaned(["1. how does TTL work?", "- \u{201C}Who runs the root servers?\u{201D}", "iPhone settings for DNS?", "How does TTL work", "what is dns"], for: request)
            == ["How does TTL work?", "Who runs the root servers?", "iPhone settings for DNS?"])
        #expect(FollowUps.cleaned(["One\nline", "Two", "Three", "Four"], for: request) == ["One line", "Two", "Three"])
        #expect(FollowUps.cleaned(["Only one"], for: request).isEmpty, "one suggestion alone isn't worth showing")
        #expect(FollowUps.cleaned([String(repeating: "long ", count: 30), "Short?", "Shorter?"], for: request) == ["Short?", "Shorter?"])
    }

    // MARK: On-device

    @Test func theOnDeviceModelReadsTheQuestionAndAnswerCutToItsWindow() {
        let long = String(repeating: "word ", count: 2_000)
        let prompt = FollowUps.prompt(for: FollowUps.Request(question: "What is DNS?", answer: long))
        #expect(prompt.hasPrefix("Their question:\nWhat is DNS?\n\nThe answer:\n"))
        #expect(prompt.count < FollowUps.answerLimit + 100)
        #expect(FollowUps.prompt(for: FollowUps.Request(question: "", answer: "A cat.")).contains("They asked about a picture"))
        #expect(FollowUps.instructions(in: .english).contains("in the language of the answer"))
        #expect(FollowUps.instructions(in: .czech).contains("Write them in Czech."))
    }

    // MARK: In the chat

    @Test func aFinishedAnswerBringsFollowUpsAndTheNextQuestionClearsThem() async {
        let model = ScriptedModel(["DNS turns names into addresses.", "Like a phone book."])
        let session = Support.session(model)
        var requests: [FollowUps.Request] = []
        session.followUpSuggester = { request in
            requests.append(request)
            return ["Who runs DNS?", "What is a resolver?"]
        }
        await Support.play("What is DNS?", in: session)
        await settleFollowUps(session)
        #expect(session.followUps == ["Who runs DNS?", "What is a resolver?"])
        #expect(requests.last == FollowUps.Request(question: "What is DNS?", answer: "DNS turns names into addresses.", asked: ["What is DNS?"]))

        session.draft = "Give me an analogy"
        session.send()
        #expect(session.followUps.isEmpty, "a new question takes the old answer's follow-ups away")
        await Support.settle(session)
        await settleFollowUps(session)
        #expect(requests.last?.asked == ["What is DNS?", "Give me an analogy"])
        #expect(model.lastMessages == ["What is DNS?", "DNS turns names into addresses.", "Give me an analogy"], "follow-ups never go to the provider")

        session.reset()
        #expect(session.followUps.isEmpty)
    }

    @Test func aClickFillsTheInputAndAShiftClickAsks() async {
        let model = ScriptedModel(["DNS turns names into addresses.", "The root servers."])
        let session = Support.session(model)
        session.followUpSuggester = { _ in ["Who runs DNS?", "What is a resolver?"] }
        await Support.play("What is DNS?", in: session)
        await settleFollowUps(session)

        session.followUp("Who runs DNS?", sending: false)
        #expect(session.draft == "Who runs DNS?")
        #expect(session.turns.count == 1, "a click only fills the input")

        session.draft = ""
        session.followUp("What is a resolver?", sending: true)
        await Support.settle(session)
        #expect(session.turns.map(\.question) == ["What is DNS?", "What is a resolver?"])
        #expect(session.draft.isEmpty)
    }

    @Test func noFollowUpsForAStoppedAnswerOrAGame() async {
        let model = ScriptedModel(["DNS turns names into addresses."])
        let session = Support.session(model)
        session.followUpSuggester = { _ in ["One?", "Two?"] }
        session.draft = "What is DNS?"
        session.send()
        session.stop()
        await Support.settle(session)
        for _ in 0..<50 { await Task.yield() }
        #expect(session.followUps.isEmpty, "a stopped answer is cut short")

        session.startGame(.wordFootball)
        await Support.settle(session)
        for _ in 0..<50 { await Task.yield() }
        #expect(session.followUps.isEmpty)
        session.followUp("One?", sending: false)
        #expect(session.draft.isEmpty, "a game takes no follow-ups")
    }

    @Test func aReopenedChatGetsNewFollowUpsAndRecentChatsKeepsNone() async throws {
        let model = ScriptedModel(["DNS turns names into addresses."])
        let session = Support.session(model)
        var calls = 0
        session.followUpSuggester = { _ in
            calls += 1
            return ["Who runs DNS?", "Set \(calls)?"]
        }
        await Support.play("What is DNS?", in: session)
        await settleFollowUps(session)
        session.reset()
        #expect(session.followUps.isEmpty)
        let chat = try #require(session.history.first)
        session.reopen(chat.id)
        await settleFollowUps(session)
        #expect(session.followUps == ["Who runs DNS?", "Set 2?"])
    }

    /// Runs `body`, then the run loop for the display cycle to lay the window out, and ends the test run if that
    /// takes longer than `seconds`, since a hung main thread can't fail a test by itself (see `AnnouncementsTests`).
    private func layOut(_ step: String, within seconds: UInt32 = 10, _ body: () -> Void = {}) {
        let done = Mutex(false)
        let watchdog = Thread {
            sleep(seconds)
            guard !done.withLock({ $0 }) else { return }
            FileHandle.standardError.write(Data("FollowUpsTests: the panel's layout never finished after \(step); ending the test run\n".utf8))
            exit(70)
        }
        watchdog.start()
        body()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        done.withLock { $0 = true }
    }

    /// An answer that ends after the window was put away brings its follow-ups into the hidden panel, and typing,
    /// asking, and a new chat take them away there too.
    @Test func followUpsComeAndGoInTheHiddenPanelWithoutHanging() async {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: ShortcutSetup.chosenKey)
        let preferences = Support.preferences()
        let model = ScriptedModel(["DNS turns names into addresses.", "Like a phone book."])
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        session.followUpSuggester = { request in ["After \(request.asked.count) questions?", "Who runs it?", "Why?"] }
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: Updater(preferences: preferences, defaults: defaults), updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        layOut("the panel is made")
        await Support.play("What is DNS?", in: session)
        await settleFollowUps(session)
        layOut("follow-ups show")
        layOut("a letter is typed") { session.draft = "W" }
        layOut("the input is emptied") { session.draft = "" }
        session.followUp("Who runs it?", sending: true)
        layOut("a follow-up is asked")
        await Support.settle(session)
        await settleFollowUps(session)
        #expect(session.followUps.first == "After 2 questions?")
        layOut("new follow-ups show")
        layOut("a new chat starts") { session.reset() }
        #expect(!controller.isVisible)
    }

    /// Waits until `condition` holds, for at most `seconds`.
    private func waitUntil(_ seconds: Double = 3, _ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(seconds)
        while !condition() && Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A suggester that answers only once the test lets it.
    private func gated(_ questions: [String]) -> (suggest: (FollowUps.Request) async -> [String], open: () -> Void) {
        let (gate, opener) = AsyncStream<Void>.makeStream()
        let suggest: (FollowUps.Request) async -> [String] = { _ in
            for await _ in gate { break }
            return questions
        }
        return (suggest, { opener.yield() })
    }

    @Test func slowFollowUpsSayTheyAreComingAndQuickOnesNever() async {
        let model = ScriptedModel(["DNS turns names into addresses.", "Like a phone book.", "The root servers."])
        let session = Support.session(model)
        let slow = gated(["Who runs DNS?", "What is a resolver?"])
        session.followUpSuggester = slow.suggest
        await Support.play("What is DNS?", in: session)
        await waitUntil { session.isSuggestingFollowUps }
        #expect(session.isSuggestingFollowUps, "they have taken longer than the loading delay")
        #expect(session.followUps.isEmpty)

        // A question asked meanwhile takes the capsule away, and the old answer's follow-ups never come.
        let next = gated(["Why a phone book?", "Who keeps it?"])
        session.followUpSuggester = next.suggest
        session.draft = "Give me an analogy"
        session.send()
        #expect(!session.isSuggestingFollowUps)
        slow.open()
        await Support.settle(session)
        await waitUntil { session.isSuggestingFollowUps }
        #expect(session.followUps.isEmpty)
        next.open()
        await settleFollowUps(session)
        #expect(session.followUps == ["Why a phone book?", "Who keeps it?"])
        #expect(!session.isSuggestingFollowUps)

        session.followUpSuggester = { _ in ["Who runs them?", "How many are there?"] }
        await Support.play("Who answers first?", in: session)
        await settleFollowUps(session)
        try? await Task.sleep(for: FollowUps.loadingDelay * 2)
        #expect(!session.isSuggestingFollowUps, "follow-ups that come at once never say they are coming")
        #expect(session.followUps == ["Who runs them?", "How many are there?"])
    }

    /// The capsule that says follow-ups are coming becomes the first of them in the hidden panel, as when the
    /// on-device model finishes after the window was put away.
    @Test func theComingCapsuleBecomesTheFirstFollowUpInTheHiddenPanel() async {
        let suite = "MeralineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: ShortcutSetup.chosenKey)
        let preferences = Support.preferences()
        let model = ScriptedModel(["DNS turns names into addresses."])
        let session = ChatSession(preferences: preferences, usage: UsageLedger(file: nil)) { model.stream($0) }
        let slow = gated(["Who runs DNS?", "What is a resolver?", "Why?"])
        session.followUpSuggester = slow.suggest
        let controller = PanelController(
            session: session, preferences: preferences,
            whatsNew: WhatsNew(defaults: defaults, currentVersion: "1.0.0"),
            updater: Updater(preferences: preferences, defaults: defaults), updateNotice: UpdateNotice(defaults: defaults),
            shortcutSetup: ShortcutSetup(defaults: defaults), openSettings: { _ in }
        )
        layOut("the panel is made")
        await Support.play("What is DNS?", in: session)
        await waitUntil { session.isSuggestingFollowUps }
        layOut("a capsule says follow-ups are coming")
        layOut("they come") { slow.open() }
        await settleFollowUps(session)
        layOut("they show")
        #expect(session.followUps.count == 3)
        #expect(!controller.isVisible)
    }

    @Test func theTestHostDrawsThemFromTheAnswer() async {
        let model = ScriptedModel(["Your Mac asks a **resolver**, which finds the address and keeps it for a while so the next visit is quicker than the first one was."])
        let session = Support.session(model)
        await Support.play("What is DNS?", in: session)
        await settleFollowUps(session)
        #expect(session.followUps.first == "Tell me more about the resolver")
    }
}
