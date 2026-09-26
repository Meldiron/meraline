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

    @Test func screenshotsBecomePictures() {
        let markdown = """
        - **Actions.** A panel of them.

        ![The panel of actions](https://raw.githubusercontent.com/Meldiron/meraline/v1.4.0/docs/screenshots/panel-light.png)

        <img src="https://example.com/shot.png" width="600" alt='Recent chats'>
        - Recent chats under the clock.
        """
        #expect(ReleaseNotes.blocks(from: markdown) == [
            .bullet("**Actions.** A panel of them."),
            .picture(URL(string: "https://raw.githubusercontent.com/Meldiron/meraline/v1.4.0/docs/screenshots/panel-light.png")!, caption: "The panel of actions"),
            .picture(URL(string: "https://example.com/shot.png")!, caption: "Recent chats"),
            .bullet("Recent chats under the clock.")
        ])
    }

    @Test func aPictureElementShowsItsImage() {
        let markdown = """
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="https://example.com/dark.png">
          <img alt="The games" src="https://example.com/light.png">
        </picture>
        """
        #expect(ReleaseNotes.blocks(from: markdown) == [
            .picture(URL(string: "https://example.com/light.png")!, caption: "The games")
        ])
    }

    @Test func onlyHTTPSPicturesAreShown() {
        let markdown = """
        ![Plain](http://example.com/shot.png)
        ![Local](file:///etc/shot.png)
        ![Relative](docs/screenshots/panel-light.png)
        ![Titled](https://example.com/shot.png "A title")
        """
        #expect(ReleaseNotes.blocks(from: markdown) == [
            .picture(URL(string: "https://example.com/shot.png")!, caption: "Titled")
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

    @Test func htmlPicturesSurviveStripping() {
        let html = "<p>New games.</p><p><img src=\"https://example.com/game.png\" alt=\"The games\"></p>"
        #expect(ReleaseNotes.blocks(from: ReleaseNotes.strippingHTML(html)) == [
            .paragraph("New games."),
            .picture(URL(string: "https://example.com/game.png")!, caption: "The games")
        ])
    }
}
