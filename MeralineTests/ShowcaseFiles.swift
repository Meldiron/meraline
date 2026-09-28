/// The files the agent in `ShowcaseTests.preview` hands over: a release page for a website, in the light and dark
/// of whoever reads it, and the same notes in Markdown.
nonisolated enum ShowcaseFiles {
    static let page = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>Meraline 1.8</title>
        <style>
          :root { color-scheme: light dark; --ink: #221d29; --muted: #6d6578; --card: #f7f3f9; --line: #e8e0ee; }
          @media (prefers-color-scheme: dark) { :root { --ink: #f3eff6; --muted: #a8a0b3; --card: #231e2a; --line: #3a3243; } }
          body { margin: 0; font: 15px/1.5 -apple-system, system-ui, sans-serif; color: var(--ink); background: Canvas; }
          header { padding: 30px 34px 26px; background: linear-gradient(120deg, #f6bfdc, #cdc4f7 55%, #bcd6f7); color: #221d29; }
          header small { font-weight: 600; letter-spacing: .08em; text-transform: uppercase; opacity: .7; }
          header h1 { margin: 4px 0 6px; font-size: 34px; letter-spacing: -.02em; }
          header p { margin: 0; font-size: 16px; opacity: .8; }
          main { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; padding: 22px 34px 30px; }
          article { padding: 16px; border: 1px solid var(--line); border-radius: 14px; background: var(--card); }
          article h2 { margin: 0 0 4px; font-size: 16px; }
          article p { margin: 0; color: var(--muted); font-size: 14px; }
        </style>
        </head>
        <body>
        <header>
          <small>What’s new</small>
          <h1>Meraline 1.8</h1>
          <p>See what an agent made before you open it.</p>
        </header>
        <main>
          <article><h2>Previews</h2><p>Pages and Markdown files show themselves right under the answer.</p></article>
          <article><h2>Nothing loads</h2><p>A preview runs no scripts and reaches no server.</p></article>
          <article><h2>A click for more</h2><p>Click a preview to see more of it, then Open or Save.</p></article>
        </main>
        </body>
        </html>
        """

    static let notes = """
        ---
        title: Meraline 1.8
        ---

        # Meraline 1.8

        **See what an agent made before you open it.** Pages and Markdown files it hands over show a preview right \
        under the answer.

        - **Previews.** The top of the page, or the first lines of the Markdown, above Open and Save.
        - **Nothing loads.** A preview runs no scripts and reaches no server.
        - **A click for more.** Click a preview to see more of it.
        """
}
