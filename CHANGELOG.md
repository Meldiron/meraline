# Changelog

Notable changes in each Meraline release, newest first.

When a version has an entry here, the Release workflow uses it as the release notes on GitHub and in the in-app update window. A version without an entry gets the list of commits since the previous tag instead. Headings are `## vX.Y.Z - YYYY-MM-DD`.

## v1.4.0 - 2026-09-26

### Ask

- **Ask about what you select.** Select text in any app and press ⌥Space, then click the text cursor above the window, or press ⇧⌘E, and the text arrives in a glass card above the mode toggle, with the app it came from, ready for a question, or just press Return. Nothing you select joins a question until you add it. The chevron shows all of it, and the cross or ⌫ in an empty input leaves it out. A sent question keeps it as a quiet quote above it. **Files work too:** with files or folders selected in Finder, the shortcut attaches them, photos in either mode and everything else when you ask an agent, and ⌫ in an empty input takes out the last one. Only what is selected when you press the shortcut comes along: let go of a selection and the next press leaves it out. Meraline needs Accessibility access to read the selection and says so in the window until you allow it; Settings › General turns the feature off. Most apps share their selection directly, and in the few that don't, such as browsers and Zed, Meraline uses the app's own Copy command, or ⌘C, and puts your clipboard back. Without Accessibility access, **Services › Ask Meraline** in any app does the same, and `meraline://ask?selection=…` hands text over from Shortcuts or a script.
- **Add the clipboard or the screen.** Beside the text cursor, two more buttons add context in one click. The clipboard (⇧⌘V) brings whatever you copied: text arrives in a card like a selection, a copied picture or file is attached as if you had pasted it. The screen (⇧⌘S) attaches a screenshot of the display the window is on, taken without Meraline's own window in it, so the model sees what you were looking at. Screenshots need Screen Recording access; the first time, a capsule beside the buttons offers to ask for it. Nothing is recorded: one picture is taken when you click, and it lives in memory with the chat.
- **Context adds up.** Each of the three buttons adds what it has now, so one question can carry text selected in two apps, a couple of copies, and a screenshot of each app you opened the window over. Click a button again while that same text, copy, or screenshot is in your question and it comes out again. A faded button has nothing to add, a plain one adds, and a pink one is already in your question. A password copied from a password manager is never read.
- **Agents read any file.** Drop a PDF, a spreadsheet, or any other file into the window, or copy it in Finder and press ⌘V, and the agent finds it in the chat's workspace, where it stays for follow-up questions. LLMs still take images only: a file dropped while you ask an LLM waits under the input with a Switch to Agent button, instead of being turned away as not an image.
- **Ask a project.** Drop a folder and ask about it. The agent works on a copy in the chat's workspace, never on your folder, and the copy stays for follow-ups until the chat leaves Recent Chats. A folder in git brings the files git keeps and its history, but not what git ignores, so a project with gigabytes of dependencies and builds copies in a second or two.
- **Actions, the way Raycast does them.** The footer under an answer offers one action, Copy Answer (⇧⌘C), and **Actions** (⌘K) for the rest, in a panel you can search and work from the keyboard: Copy Conversation, **Ask Again** (⌘R) for a fresh answer from the provider you're on now, New Chat, **Show Agent's Files in Finder** (⇧⌘O) for an agent's chat, and **Delete Chat** (⇧⌘⌫), which asks first and keeps the chat out of Recent Chats. A game's panel has Hint, Play Again, Copy Game, End Game, and Delete Game. The sparkle opens the same kind of panel, with the providers of the mode you're in, the other mode, anonymous mode, and Settings.
- **Recent chats under the input.** A clock beside the games shows how many of your last five chats are kept. Click it for the same kind of panel: pick a chat to reopen it, or Clear Recent Chats, which asks first. Shaking the window while you drag it clears them too. Either way the count rolls to zero and the clock says so.
- **Anonymous mode.** Turn it on from the sparkle or with ⇧⌘N, and the chat you're in skips Recent Chats when it ends, along with every chat after it until you turn it off. The sparkle goes graphite, with sunglasses cut out of it, and the input says "Ask anything secretly…". It lasts until you turn it off or quit, and isn't saved with your settings.
- **A shortcut that works from the first launch.** ChatGPT, Gemini, Copilot, Raycast, and Alfred all want ⌥ Space too, and macOS hands it to whichever app took it last, so Meraline could look broken. The first time it opens, Meraline checks whether ⌥ Space looks taken on your Mac and, if so, offers ⌥ ⇧ Space and a couple of others, or one you record. Pick one and press it once to see the window answer. Put the picker away and a small capsule under the input offers to change the shortcut later.
- **Claude Code runs commands and skills.** In Agent mode, Claude Code can run scripts and shell commands in the chat's workspace and use the skills installed in it. Before a command that changes anything, or a skill, the window shows the exact command or the skill's name with Allow and Deny.
- **The input stays on one line.** A long question scrolls sideways instead of wrapping, like Spotlight or Raycast. Pasted text with line breaks shows each one as ⏎ and keeps them in what you send, so code and logs arrive as you copied them.
- **What's new stays in the window.** After an update, a What's New capsule beside the pin opens the release notes under the input, instead of a window of its own that showed them empty. The cross or Got It puts it away until the next update.
- Agent mode wears a robot head instead of a terminal prompt.

### Play

- **Speed Definitions.** The model shows a word, you define it in ten words or fewer, and it grades you out of 10, then shows its own definition. Five words a game; pass skips one. Using the word to define itself comes back to you.
- **Letter Auction.** The model is the banker: it deals a shared pool of letters, each with a price, and you take turns spending them on words. A word banks what its letters are worth and they're gone for both of you, so the rare ones go fast. Meraline keeps the books, and a banker's word the pool can't pay for banks nothing. Type pass to close the bank; Hint shows a word the deal still makes.
- **Play Again.** When a round is over, a tray under the game shows how it went, your tally against the model since Meraline opened ("You 2 – 1 Model"), and Play Again (⌘R). After the game ends it stays on the empty window, ready for a rematch, until you start another game or put it away with its cross. Like everything else, the tally is gone when you quit.
- **Rhyme Duel tells a story.** The model's lines end on short, easy words, and after you rhyme with one it carries the story on with a line that ends on a new word, so every couplet is a fresh rhyme instead of one sound for the whole duel. Stuck? **Hint** (⌘I) shows a word that rhymes, a different one each time you press it, and a line that ends on one of the model's rhymes always counts.
- **The games fold away.** The row under the input shows only the controller until you click it. The glass then stretches out to the left and the games come out from under it one by one, nearest first; click again and they fold back the same way. Meraline remembers which you left open until it quits, and the controller turns pink while a game is on behind it.

### Fixes

- The pin and Settings buttons beside the input, and the cross on an attached image, respond to a click anywhere in their glass circle, not only on the icon.
- The window no longer jumps when something opens under the input, such as a picture you attach or a notice: the input stays still while the card grows beneath it, and whatever you take out fades away instead of being cut off at the window's edge.

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
