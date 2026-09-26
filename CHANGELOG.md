# Changelog

Notable changes in each Meraline release, newest first.

When a version has an entry here, the Release workflow uses it as the release notes on GitHub and in the in-app update window. A version without an entry gets the list of commits since the previous tag instead. Headings are `## vX.Y.Z - YYYY-MM-DD`.

## Unreleased

### Ask

- **Claude Code runs commands and skills.** In Agent mode, Claude Code can run scripts and shell commands in the chat's workspace and use the skills installed in it. Before a command that changes anything, or a skill, the window shows the exact command or the skill's name with Allow and Deny.
- **The input stays on one line.** A long question scrolls sideways instead of wrapping, like Spotlight or Raycast. Pasted text with line breaks shows each one as ⏎ and keeps them in what you send, so code and logs arrive as you copied them.
- **What's new stays in the window.** After an update, a What's New capsule beside the pin opens the release notes under the input, instead of a window of its own that showed them empty. The cross or Got It puts it away until the next update.

### Play

- **Rhyme Duel tells a story.** The model's lines end on short, easy words, and after you rhyme with one it carries the story on with a line that ends on a new word, so every couplet is a fresh rhyme instead of one sound for the whole duel. Stuck? **Hint** (⌘I) shows a word that rhymes, a different one each time you press it, and a line that ends on one of the model's rhymes always counts.

## v1.3.0 - 2026-09-26

### Ask

- **Agents bring their MCP servers.** Claude Code, Codex, and OpenCode answer with the MCP servers set up in them. Settings › Agents lists each agent's servers as the agent itself reports them, with a switch per server and an Allow MCP servers switch above; Meraline never edits the agent's own configuration. While an agent works, the window says which server it is asking ("Asking github to search issues"), and the tools an answer used sit under it as small capsules. The sparkle menu shows how many servers an agent may use.
- **A workspace for every chat.** Each chat gives its agent an empty temporary folder to work in, kept for as long as the chat is open or in Recent Chats, and gone when the chat is or when Meraline quits. Claude Code can read and write there, and Codex's sandbox allows writes only there and in the temporary folders.
- **Agents ask, you decide.** When Claude Code wants to write a file, or anything else it needs leave for, the window shows what it asks and offers Allow and Deny. A question of its own comes with its choices as buttons and a field for an answer of your own. OpenCode's run mode can't ask and turns such requests down itself, which the window says. How each ask was settled stays under the answer.
- **LLM or Agent.** A glass toggle under the input switches between asking a model and asking an agent (⌘1 and ⌘2). Each mode remembers its own provider, and the sparkle menu lists only the ready providers of the mode you're in. Settings › General picks a default for each.
- Settings groups providers under LLMs and Agents.
- `meraline://settings?pane=claudeCode` opens Settings on a page: `general`, `prompt`, `updates`, `about`, or any provider.

### Play

- **Games have their own buttons.** The six games moved out of the sparkle menu into a glass group of icon buttons on the right of the new row, behind a controller. Hover one to see what it is; the game you're playing stays highlighted.

### Fixes

- Opening Settings on a provider's page no longer focuses its model field and pops open the list of suggested models.
- Answers from command-line agents arrive line by line as they are written, instead of sometimes waiting for the next line.

## v1.2.0 - 2026-09-26

### Ask

- **Thinking out loud.** While a model is still thinking, the window murmurs a different line every few seconds: "sharpening pencils…", "asking the void…", "consulting the sparkle council…". Searches, pages, and commands still show what is really happening.

### Play

- **Rhyme Duel.** Pick it from the sparkle menu and the model opens with a line of verse. Answer with one that rhymes, and so on, four lines each; the last word is yours. A line that doesn't rhyme comes back to you instead of costing a turn (send it again to insist), and Esc forgets the duel like any chat. Return after the last line starts a rematch.
- **Add-a-Word.** The model writes the first word, and you take turns adding one word each until someone ends the sentence with a period. The model scores how much sense it makes out of 10, and Return starts the next sentence of the same story.
- **Categories.** The model picks a category, like Kitchen, and you take turns naming things in it, six each. The model checks yours; one that doesn't fit comes back to you. A repeat is caught before anything is sent, and typing pass gives up the round.
- **Word Football.** The model kicks off with a word, and each word after it must start with the last letter of the one before. Your chain is checked on your Mac and the model referees whether your word is real. A model word that breaks the chain is a foul, and you win.
- **Odd One Out.** The model sets three words and you tap the one that doesn't belong; then you set three and say whether the model got it. Three rounds each, with a running score.
- **Fix the Typo.** The model writes a sentence with one misspelled word, and you type it spelled right. Five sentences a game; pass shows the answer.
- Every game keeps its answer hidden until you've played, runs only in memory like any chat, never touches the prompt in Settings, and ends with Esc or End Game.

## v1.1.0 - 2026-09-26

### Ask

- **Apple Intelligence.** The on-device model built into macOS is a provider now: private, works offline, needs no key, and is on by default on Macs that support it, so a fresh install can answer before any key is added. Other providers you set up take precedence over it.
- **Fresh starts.** After the window has been hidden for a while (30 minutes by default, adjustable in Settings › General), the chat moves to Recent Chats and your next question starts fresh.
- **Copy Conversation** (⌥⇧⌘C) copies the whole chat as Markdown.
- Codex can search the web when the toggle on its page is on.
- The Answers pane is now called Prompt, and the Settings window is titled after the pane you're on.

### Install and update

- **A proper installer.** Releases ship as a styled disk image, signed and notarized, alongside the zip. Homebrew users can `brew install --cask meldiron/tap/meraline`.
- **Quiet updates.** Updates download and install in the background. The menu bar menu and Settings › Software Update show when one is ready, and after an update Meraline shows what changed.
- **Beta channel.** Settings › Software Update › Update channel switches to early builds ahead of each release.

### Automate and diagnose

- **`meraline://` URLs.** `meraline://ask?text=…&send=1` asks a question from Shortcuts, Raycast, or a script; `meraline://new` and `meraline://settings` do what they say.
- **Copy Diagnostics** in Settings › About produces a report for bug reports, with no keys, questions, or answers in it.

## v1.0.0 - 2026-09-25

The first release. Press ⌥ Space, ask, and let it go.
