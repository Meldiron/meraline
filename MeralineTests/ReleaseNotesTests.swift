import Foundation
import Testing
@testable import Meraline

struct ReleaseNotesTests {
    @Test func splitsMarkdownIntoBlocks() {
        let markdown = """
        ## What's new

        - Press **⌥ Space** anywhere
        * Paste an image
        Answers stream in
        as they are written.

        Thanks for trying it.
        """
        #expect(ReleaseNotes.blocks(from: markdown) == [
            .heading("What's new"),
            .bullet("Press **⌥ Space** anywhere"),
            .bullet("Paste an image"),
            .paragraph("Answers stream in as they are written."),
            .paragraph("Thanks for trying it.")
        ])
    }

    @Test func screenshotsAreLeftToGitHub() {
        let markdown = """
        - **Actions.** A panel of them.

        ![The panel of actions](https://raw.githubusercontent.com/Meldiron/meraline/v1.4.0/docs/screenshots/panel-light.png)

        <img src="https://example.com/shot.png" width="600">
        - Recent chats under the clock.
        """
        #expect(ReleaseNotes.blocks(from: markdown) == [
            .bullet("**Actions.** A panel of them."),
            .bullet("Recent chats under the clock.")
        ])
    }

    @Test func emptyNotesProduceNoBlocks() {
        #expect(ReleaseNotes.blocks(from: "\n\n  \n").isEmpty)
    }

    @Test func stripsHTML() {
        let html = "<p>Faster <b>answers</b> &amp; fewer bugs.</p><ul><li>One</li><li>Two</li></ul>"
        let text = ReleaseNotes.strippingHTML(html)
        #expect(text.contains("Faster answers & fewer bugs."))
        #expect(ReleaseNotes.blocks(from: text).contains(.bullet("One")))
        #expect(ReleaseNotes.blocks(from: text).contains(.bullet("Two")))
    }
}
