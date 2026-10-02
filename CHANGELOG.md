# Changelog

Notable changes in each Meraline release, newest first.

When a version has an entry here, the Release workflow uses it as the release notes on GitHub and in the in-app update window. A version without an entry gets the list of commits since the previous tag instead. Headings are `## vX.Y.Z - YYYY-MM-DD`.

## Unreleased

### Ask

- **A colon opens the Context card.** End a question in a colon, “Fix the grammar:” or “Find the bugs in this:”, in LLM or Agent mode, and the Context card opens under the input for the text, as a preset does when there is nothing to work on yet. The cursor stays in the input; Tab moves to the card.
- **Tab closes an empty Context card.** Tab in the card with nothing written in it goes back to the input and takes the card away, so Tab opens and closes it. A card with text stays, as before.
- **The window fades in and out.** ⌥ Space fades the window in as the card rises into place, and fades it out as it closes, instead of showing and hiding it in a cut. Pressing the shortcut during the fade turns it around. With Reduce Motion only the fade remains.
- **Fewer cuts in the chat.** A chat's first question brings the conversation in smoothly, the thinking line fades into the answer's first words, and Show What Changed and Show Answer fade one into the other. An agent's ask, its tools, and the files it hands over fade in too.

### Decision

- **The scope switch explains itself.** Click Each Word, Each Line, or back to Whole Text under the input, and a note under the cards says what the choice decides about, up to the thousand words or lines a question takes. It goes with the question or the chat, and never shows on its own.
- **Decisions as you type.** The Context card has a Live switch in Decision mode. Turn it on, and after each pause in typing the card asks the decision model about its text, without sending anything to the chat, and shows the answer on a chip under the text: a check in green for Yes, a cross in red for No, how sure it is beside it. The question in the input is asked, and so is any preset you turn on: click Urgent?, Tone, or Priority on the card and watch a draft message decided three ways at once, in one request. An answer stays while its text and question stay, so turning a preset on asks only that preset; typing again asks everything that is on. Return still asks for a decision in the chat. Off until you turn it on, since every pause asks the model, and Settings › Usage counts the live decisions among the rest.

## v1.10.0 - 2026-10-02

### Ask

- **The Context card takes the keyboard.** Tab, Decision's Write It, and Add Text in the sparkle's panel open the card under the input with the cursor in it, so you can paste or type at once; the cursor used to stay in the input. Tab in the card goes back to the input.

![The Context card under the input with the cursor in it, holding a message written by hand, and a question above it asking for a friendly reply](https://raw.githubusercontent.com/Meldiron/meraline/v1.10.0/docs/screenshots/add-text-light.png)
- **What changed stands out.** In Show What Changed, the text that stayed as it was is now gray, and the words that went and came sit on deeper red and green, so three edits in a long page are found at a glance instead of hunted for among white text. The strike through what went stays.

![A grammar fix shown as the selected text: the words that stayed in gray, the words that went struck through on red, the words that came on green, and Show Answer under it with how much changed](https://raw.githubusercontent.com/Meldiron/meraline/v1.10.0/docs/screenshots/what-changed-light.png)
- **Presets open the Context card.** Click Fix Grammar, Anti-Slop, Find Bugs, or any other preset with nothing to work on yet, and the Context card opens under the input with the cursor in it, ready for the text. With text selected or copied, or a file or picture attached, the preset fills the input as before. The default presets now end as sentences rather than a colon, since the text comes on the card, not after them.

![Fix Grammar put in the input with nothing to work on yet, and the Context card open under it with the cursor in it and the text pasted in](https://raw.githubusercontent.com/Meldiron/meraline/v1.10.0/docs/screenshots/preset-text-light.png)

### Decision

- **The surest first.** When Jev decides about each word or line, each answer lists its words or lines surest first, so the clearest calls lead and the near misses sit at the bottom. Copy Answer lists them the same way.
- **Answers fold.** Each answer's words or lines now sit folded under its header, the count beside it, so a long text's decisions read as a short summary first. Click a header to open its words or lines, and again to fold them back.

![Decision mode about each line: six tasks from Notes under Yes, No, and Not sure, Yes open with its three tasks and how sure Jev is of each, the others folded to their counts](https://raw.githubusercontent.com/Meldiron/meraline/v1.10.0/docs/screenshots/decision-lines-light.png)
- **Decision models through OpenRouter.** Settings › Decision Models has OpenRouter beside TypeSafe, on the key you use for OpenRouter’s LLMs, pasted once for both. Pick TypeSafe’s Jev, Liquid’s D1, Upstage’s Solar Decide, Together’s Tev1, or Jared Palmer’s Kev, every decision model OpenRouter serves, and Settings › Usage counts what each answer cost as OpenRouter reports it.
- **Decisions on this Mac.** Settings › Decision Models has Ollama too: turn it on, and Bespoke Labs’ Nimble or Together’s Tev1 decides on your Mac, with no key and nothing leaving it, as Ollama’s LLMs answer. It takes Ollama 0.35 or newer and a model pulled in Terminal, “ollama pull nimble” (9 GB) or “ollama pull tev1” (4 GB, or “tev1:0.8b” for a small one). A decision about each word or line goes eight at a time, since Ollama’s models read a request in prompts of 2,050 tokens, and Settings › Usage counts them as free.

![Settings › Decision Models: TypeSafe, OpenRouter, and Ollama in the sidebar, and Ollama's pane with Use Ollama turned on, nimble as its model, and under it what to pull in Terminal](https://raw.githubusercontent.com/Meldiron/meraline/v1.10.0/docs/screenshots/decision-models-light.png)

### Fixes

- Shadows fade out instead of ending in a line. The window keeps room for its shadows now: under the card, under the time-left and cost capsules below it, beside the presets, and around a panel of actions, where the shadow was cut off at the window's edge.

## v1.9.0 - 2026-09-29

### Ask

- **Press Tab to add text to your question.** Tab in the input opens a card for context written by hand, such as a quote, an email, or a snippet to work on, and it goes with your question in LLM and Agent modes the way selected or copied text does. ⌘Return sends from the card, and Return makes a new line there. Tab no longer sends, since Return already does. Add Text in the sparkle's panel opens the same card.

![The Context card under the input, holding a message written by hand, with a question above it asking for a friendly reply](https://raw.githubusercontent.com/Meldiron/meraline/v1.9.0/docs/screenshots/add-text-light.png)

- **Whole documents come along.** Text you add from a selection, the clipboard, or the window used to stop at 20,000 characters. A long report or transcript now arrives in full, up to a million characters.
- **Clearer placeholders.** Each mode's empty input reads the same way: “Ask to get answer…” for LLMs, “Ask to do work…” for agents, and “Ask to make decision…” for Jev. Selected text and follow-ups still tailor it.

### Decision

- **Ask without context.** A decision no longer needs text to decide about. Ask a question that stands on its own, such as “Is 17 prime?”, and Jev decides it as it is. The text you select, copy, or write still sharpens the call, and the row under the input suggests it, now as optional.
- **A scale for levels in order.** When a question names its answers in order (“How high a priority is this? Low < Medium < High”), Jev's answer shows on a scale: the levels from first to last, a marker where Jev placed the text, between two levels when it isn't sure, and each level's share beneath it.

![A message from Slack placed on a scale from Low to High, the marker just short of High, with each level's share beneath it](https://raw.githubusercontent.com/Meldiron/meraline/v1.9.0/docs/screenshots/decision-levels-light.png)

- **Your own answers show how sure Jev is.** For answers you named, a set with `/` or levels with `<`, the disc, its ring, and the scale's meter turn green when Jev is very sure and amber when it's only moderately sure. Yes and No keep their green and red.

### Speed

- **The first open is as quick as the rest.** Meraline builds and draws its window once, off screen, right after it launches, so the first ⌥ Space no longer waits for it.
- **The window opens the moment you press the shortcut.** Reading what you selected no longer holds it up. When an app has to be asked to copy, as browsers and editors do, that now happens after the window is up, and the selection is offered a moment later. Zed still reads first, since the ⌘C has to reach it.

### Fixes

- New answers scroll into view again. After a few answers, the conversation stopped following along to the newest one.
- The cursor in the Context card sits on its first line. It blinked a line's gap above “Paste or type…”, and typing started there too. In LLM and Agent modes the hint now reads “Paste or type text to send with your question…” instead of asking for text to decide about.

## v1.8.0 - 2026-09-29

### Decision

- **Decision mode, with TypeSafe’s Jev.** The toggle under the input has a third mode beside LLM and Agent (⌘3): Decision. Add the text you selected or copied with the buttons above the window, or write it in the window, ask a question, and Jev, TypeSafe’s decision model, answers in a fraction of a second, not in words but with a decision: a check on green glass for Yes or a cross on red for No, ringed by how sure it is, with “82% confident” beside it and every answer’s probability under it. Under the confidence you set in Settings › Prompt › Decisions, the answer says Not Sure and which way it leans. Yes and No are the answers unless the question names its own after its question mark, with / between them (“Which team should handle this? Billing / Technical / Sales”) or < for levels in order (“How urgent is this? Low < Medium < High”); the capsule under the input shows which answers the question picks from, and Settings sets the ones a question that names none picks from. A decision needs text, so nothing is sent without it, pictures and files wait for another mode, and the screenshot button steps aside. Follow-ups ask about the same text, Copy and Insert give the answer in words, and Settings › Usage counts decisions, with Jev at TypeSafe’s list price. Paste your TypeSafe API key in Settings › Decision Models to start.

![Decision mode: asked whether a message selected in Mail is urgent, Jev answers Yes, a check on green glass ringed by its confidence, 82% confident, with Yes 91% and No 9% under it](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/decision-light.png)

![Decision mode: a message from Slack placed along Low, Medium, and High as a high priority, and under the input the answers the next question picks from: Now, After lunch, Tomorrow](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/decision-levels-light.png)

- **Decide about each word, or each line.** A switch at the games’ place in Decision mode decides about the whole text, each of its words, or each of its lines: Jev answers the question for every one, a hundred at a time, and the card fills in as they come, the words or lines grouped by answer, Yes on green and No on red, each with how sure Jev is. Up to 1,000 words or lines a question; `meraline://ask?mode=decision&scope=lines` picks the scope too.

![Decision mode about each line: six tasks from Notes grouped under Yes, No, and Not sure, each with how sure Jev is, and the switch under the input set to each line](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/decision-lines-light.png)

### Ask

- **Presets for your first question.** Glass capsules above the window's top right, beside the gear, hold the prompts you'd otherwise type again and again: Fix Grammar, Anti-Slop (strips the filler, buzzwords, and em dashes that give AI writing away), Anonymize, and Translate, into the language set in Settings › Prompt. Click one to put its text in the input, ahead of anything you typed, and add the text to work on, or select it in another app first; Shift-click to send it at once; while Shift is down, the one under the pointer turns pink and points up. Click it again to take it out. They're for starting a chat, so they sink into the window once it starts and come back for the next one. Settings › Prompt › Presets edits them, adds your own with an icon of your choice, moves them along the row, and deletes them.

![Preset capsules above the window's top right beside the gear, one chosen with its text in the input above selected text](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/presets-light.png)

- **Presets for each mode.** LLM, Agent, and Decision each have presets of their own above an empty chat, and a change of mode sinks one row into the window as the next rises. Agents start with Find Bugs, Explain Code, Write Tests, and Research; decisions with Urgent?, Scam?, Tone, and Priority, two of which name their answers after the question. Settings › Prompt edits each mode’s list.

![Settings › Prompt: the presets for each mode, each with an icon and a name, and the controls to add, move, and delete them](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/prompt-presets-light.png)

- **⌘1 to ⌘9 run your presets on an answer.** Once an answer is ready, Actions (⌘K) lists the presets after Make Shorter and the other rewrites, and ⌘1 to ⌘9 run the first nine without opening it: Fix Grammar, Anti-Slop, Anonymize, or Translate the answer, or run one of your own on it. What comes back takes the answer's place, as a rewrite does, and if you stop it or it fails the old answer returns. They go by the keys' places, so they work on any keyboard layout; meanwhile ⌘1 and ⌘2 leave the LLM and Agent toggle, which they switch again once a new chat starts.
- **Follow-up questions under an answer.** Once an answer is done, two or three questions you might ask next wait under it, suggested on your Mac and never by your provider: by Apple Intelligence when it's on, and otherwise from the answer itself, its code, the terms it sets in bold, and the kind of question you asked (in English). Click one to put it in the input and change it before you ask, or Shift-click to ask it right away; while Shift is down, the one under the pointer turns pink and points up. While Apple Intelligence is still thinking of them, one chip says so, and it becomes the first of them. They go the moment you type or ask, live in memory only, and a chat reopened from Recent Chats gets new ones.

![A finished answer with follow-up questions suggested under it, worked out on the Mac](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/follow-ups-light.png)

- **See what an answer changed.** Ask to fix the grammar of text you selected or copied, and **Show What Changed** under the answer, or ⌘D, puts your text in its place with each word that went struck through in red and each that came in green, so a fix is quick to check before you paste it. **Show Answer** brings the answer back. Beside the button, how much changed, in numbers: “5% changed · 6 edits”, where a typo counts only the letters that differ. It shows only when the answer is your text changed, not an explanation, a summary, or a translation of it, and the follow-ups and rewrites that rework the same text get it too.

![A grammar fix shown as the selected text with words struck through in red and added in green, and Show Answer under it with how much changed](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/what-changed-light.png)

- **Tear off several answers into one note.** Tear off another answer while a note is open and it goes on top, with the edges of the ones behind it peeking out under the card. A count badge in the note's header, such as 1/3, brings the next one forward and Shift-click the one before, as ⌃⇥ and ⌃⇧⇥ do while the note has the keyboard, so you flip through them without opening the window. Esc, ⌘W, or the cross put away the answer in front, and Option-click on the cross the whole pile.

![Three answers piled up in one torn-off note, the edges of two peeking out under the card and a count badge in the header](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/note-stack-light.png)

- **Zoom answers to read them across the room.** ⌘+ and ⌘− make answers larger or smaller, from 85% to 300%, and ⌘0 brings them back to their own size; pinching on the trackpad zooms too. Their text, code, and tables grow while the rest of the window stays as it is, and a capsule in the footer shows the zoom and goes back to 100% when clicked. A torn-off note opens at the window's zoom, then zooms on its own and widens with it.
- **Paths in answers open with a click.** A path to a file or folder on your Mac, such as `~/Downloads/report.pdf`, becomes a link in the answer: click it to open it in its app, or ⌘-click to show it in Finder. In an agent's chat, paths inside the folder it works in count too, line numbers and all (`src/app.swift:42`), and so do the links it writes to its files. They open the way handed-over files do, so apps are only shown in Finder and scripts open as text, and they're found as the answer is drawn and kept nowhere. `meraline://` links in answers work too, but a question one fills in waits for you to press Return.
- **Drag text in.** Drag a selection from any app onto the window, anywhere on it, the input included, and it waits above your question in a card of its own, with the app it came from, just like text you select and add with the button above the window. Drop more and each gets a card of its own, and a picture dragged from a web page still attaches as a picture. Files and pictures dropped right on the input now attach too, instead of landing in it as text.
- **Services › Ask Meraline takes pictures.** Select part of an image in Preview, or a photo in Photos, and choose Ask Meraline from the app's Services menu: the picture is attached to your next question, for any model, as text already was. The same picture comes only once, and a selection with both words and a picture still comes as words.
- **Stash a draft for later.** Press ⌘S with no chat open to put what you typed, and the selected text, clipboard, screenshots, and files you added, in Recent Chats, and start on something else. Reopen it from the clock and it's all back in the input. It waits there for 30 minutes, like any recent chat, and reopening another chat stashes what you had typed in an empty one, so it isn't lost. Anonymous mode keeps drafts out of Recent Chats too.
- **What today has cost, under the window.** Before a chat starts, two glass capsules under the window's bottom right, where a chat's timer shows, say what LLMs and what agents have cost today, as Settings › Usage counts it: the mode's symbol and the amount, nothing more. Until either has cost a tenth of a cent, one capsule says $0 today, and everything starts over at midnight. There's nothing to set, and they never stop you from asking.

![Two glass capsules under the window's bottom right before a chat starts, one for LLMs and one for agents, each a symbol and what it has cost today](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/cost-nudge-light.png)

- **+5 min and +30 min for a chat you still need.** Two glass buttons beside the timer under the window's bottom right add 5 or 30 minutes to the open chat, as often as you like, and the timer shines pink for a moment as its minutes roll up, and your next message never takes the extra time away; a chat you close keeps it in Recent Chats. The timer itself no longer takes a click.
- **`meraline://mode?mode=decision`.** The URL scheme names modes: `mode=llm`, `mode=agent`, or `mode=decision` on `meraline://ask` and `meraline://mode`, beside the `agent=1` switch; `meraline://mode` alone now goes around the toggle.

### Agents

- **See a page or a note before you open it.** When an agent hands over an HTML page or a Markdown file, its card now shows a glass preview strip above Open and Save: the top of the page as a browser draws it, or the note's first lines drawn like an answer. Click the strip to see more of it. The page runs none of its scripts and loads nothing from the internet, only pictures and styles from the agent's own folder, so looking at it tells no one.

![An agent's handed-over HTML page and Markdown file, each with a glass preview strip above Open and Save](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/preview-light.png)

- **Why? on the tools an answer used.** Once an agent's answer is done, click any of the tools under it, a web search, a page, a command, an MCP tool, and the agent that used it says in one line why, right under them; click it again to fold the line away. Claude Code answers in the same quick run as Why? on its asks, and Codex and OpenCode in a run of their own without the web or MCP servers, so your chat goes nowhere it didn't go already.

### Privacy

- **Forget chats when you step away.** Settings › General › Privacy can forget every chat when the Mac sleeps or its display turns off, when the screen locks or you switch to another user, or both. The chat in the window and what's typed in it, Recent Chats, torn-off answers, and the folders agents worked in all go at that moment. Both are off unless you turn them on, and quitting, restarting, shutting down, or logging out forgets chats as always.

### Updates and diagnostics

- **Stable or Beta at a glance.** Settings › Software Update opens on a chip that says whether your copy is a stable build or a beta, with the tag of its GitHub release, such as v1.8.0-beta.1, and a click opens that release, so its notes and downloads are there without looking through the pre-releases. One switch, Get beta updates, takes the place of the Update channel menu. Turn it off on a beta and the pane says the beta stays until a newer stable release comes out.

![Settings › Software Update opening on a chip that reads Beta with the release tag, and one Get beta updates switch](https://raw.githubusercontent.com/Meldiron/meraline/v1.8.0/docs/screenshots/software-update-light.png)

- **Copy Diagnostics whenever you like.** The sparkle's panel copies the diagnostics report at any time, not only after a crash, and the capsule under the card says Copied. It still holds no questions, answers, or keys, and it now writes your home folder as `~` in the log's paths too.

### Fixes

- **A robot the size of its neighbours.** The robot of Agent mode was drawn a third smaller than the speech bubble beside it. It is now as big as the system's own symbols, in the mode toggle, the cost capsule, and the sparkle's panel alike.
- **Long text stays inside the input.** Once the input's prompt changed at the moment it emptied, as when you stash a draft about selected text, the next long line in it, such as a preset's, ran under the pin and the gear and past the window's edge, and didn't scroll to the cursor. It scrolls inside the input again.

## v1.7.0 - 2026-09-28

### Usage

- **Settings › Usage.** A new pane counts how Meraline is used, by the hour, day, week, month, or year: questions and chats, answers and the words in them, tokens in and out with a chart along the span, and what they cost. Claude Code, OpenCode, and OpenRouter say what each answer cost; the rest is worked out from tokens at OpenRouter's public prices, and Apple Intelligence's answers are estimated from their length. Below, the models and what each cost, the agents' runs, tools, asks, and files handed over, what went with your questions, and habits: your busiest hour and weekday, days with Meraline and the longest streak, time spent waiting and reading, and answers copied, inserted, and torn off. The counts live in one file on your Mac, numbers only, never a word of what was asked or answered, and Clear Usage Data deletes it. `meraline://settings?pane=usage` opens the pane.

![Settings › Usage over the last 30 days: questions, answers, tokens in and out, cost, and rounds, with a chart of tokens by day](https://raw.githubusercontent.com/Meldiron/meraline/v1.7.0/docs/screenshots/usage-light.png)

- **Your games, in numbers.** Each game you played gets a section of its own there, with its rounds, your win rate and best run of wins, and numbers of its own, such as Rhyme Duel's average score, the letters in your Longest Word words, or the typos you fixed in Fix the Typo.

![Settings › Usage further down: the game played most and the best record, then Longest Word's rounds, win rate, best run, and the letters in your words and the model's](https://raw.githubusercontent.com/Meldiron/meraline/v1.7.0/docs/screenshots/usage-games-light.png)

### Settings

- **Answers in your language.** Settings › Prompt starts with Language: English, Czech, Slovak, and 22 more. LLMs and agents answer in it unless you ask for another, as for a translation, and the games are played in it. It's added after your instructions, so ones you changed keep it too.
- **Instructions for LLMs and for agents.** Settings › Prompt now keeps one set of instructions for LLMs and another for Claude Code, Codex, and OpenCode, so quick answers can stay short while an agent says what it did. Agents start from instructions of their own that lead with what they did and what came of it. If you had changed the prompt, your version carries over to both.

![Settings › Prompt: the language answers are in, then one set of instructions for LLMs and another for agents](https://raw.githubusercontent.com/Meldiron/meraline/v1.7.0/docs/screenshots/prompt-light.png)

- **Every prompt in one place.** Below them are the rules of each of the eight games and the instructions Why? uses to explain an agent's ask. Each is folded under its name, says Changed once you edit it, and has Restore Default to go back. A game still reads the model's moves in the format its rules ask for, such as “OK: ” or the “ | ” before a hidden answer, so keep those as they are. Copy Diagnostics names the prompts you changed, never what they say.

![Settings › Prompt further down: the eight games, with Word Football's rules changed](https://raw.githubusercontent.com/Meldiron/meraline/v1.7.0/docs/screenshots/prompt-games-light.png)

### Games

- **Longest Word replaces Letter Auction.** Your Mac draws nine letters, and you and the model each make the longest word you can. The model picks first and its word stays hidden until you play yours, so a round is quick and fair. The letters sit in glass bubbles, and the shuffle button beside them deals them out in a new order, hopping over and under each other, whenever you need a fresh look. Your Mac checks both words with macOS's dictionary, in your language, and afterwards shows a longer word when it knows one. Hint says how long a word hides in the letters and how it starts, and a word the dictionary doesn't know counts if you send it again. No prices to add up, no pool to keep track of. Links made for Letter Auction start Longest Word.

![Longest Word: nine letters in glass bubbles with the shuffle button beside them, while the model's word stays hidden](https://raw.githubusercontent.com/Meldiron/meraline/v1.7.0/docs/screenshots/longest-word-light.png)

- **Make the first move.** Every game but Longest Word now waits for you to open it: write Rhyme Duel's first line, name a category, type the first word of an Add-a-Word sentence, kick off Word Football, or set the first Odd One Out puzzle. Or press Return, or the Random button in the game's card (Random Rhyme, Random Word, Random Category, Random Puzzle, or Random Sentence), to leave it to the model or the dice. Once a round is over, what you type opens the next one. In Rhyme Duel whoever opens sets each rhyme and the other answers it, so when you start, you pick the sounds and the model rhymes with you. In Categories the model always names the first thing, and a category it won't play comes back to you. In Odd One Out you take turns, so whoever starts sets rounds one, three, and five. A random kickoff in Word Football is never one of that chat's earlier matches while others are left.

![Rhyme Duel waiting for its first move: a card that explains the duel, with a Random Rhyme button](https://raw.githubusercontent.com/Meldiron/meraline/v1.7.0/docs/screenshots/opening-light.png)

- **Stump the model in Fix the Typo.** Type a sentence with one misspelled word, and the model hunts for it; tap It found it or It missed. Before each of the five sentences you choose again: type one of your own, or press Return (or Random Sentence) for one of the model's to fix, so a game can mix both. The footer counts what you fixed and what the model found, and the game goes to whoever won more sentences.
- **Give the words in Speed Definitions.** Type a word, and the model defines it in ten words or fewer; tap It got it or It missed. Start that way and you give all five words, or press Return (or Random Word) to define the model's as before.
- **Rhyme Duel rates how you played.** Once the eighth line is in, the model scores your lines out of 10 and gives one quick idea for your next duel, quoting your own words, such as trading “for goodness’ sake” for a fresher detail. The score and the tip show under the poem, and Play Again says the score. Copy still takes just the poem.
- **Games play out differently every time.** Asked the same thing, a model answers the same way, so Meraline now rolls the dice itself. Each Rhyme Duel gets a story drawn on your Mac, such as a retired pirate in a laundromat who loses a bet, and each of the model's lines ends on one of three words of a sound no line has used yet. Hint knows the other words of that sound, so it always has a rhyme to offer. In Word Football, each word the model plays leans toward a kind drawn for it, an animal, a tool, a feeling, so no two matches run alike. Categories draws its category from more than a hundred, never one you've played in that chat until they run out. Each Odd One Out puzzle the model sets gets a theme, from gemstones to pirates, and a way to link the two that belong, such as what they're made of or a word hidden inside them. Speed Definitions deals the model three of more than 300 words to pick from, so serendipity no longer opens every game.
- **Speed Definitions mixes easy, medium, and hard words.** Most words are medium, one in five is easy, like umbrella, and one in five is hard, like ephemeral. Each word's heading says which.
- **Rhyme Duel lines are shorter.** The model used to answer a line with a sprawling one that buried its rhyme. Its rules now ask for the line of nursery rhymes and ballads: four beats, about eight syllables, one plain thing said in the order you would speak it, landing on the rhyme word. Sonnet's openings came down from eleven or twelve syllables to eight. Settings › Prompt shows the rules, if you want to tune them.
- **Hint shows more rhymes.** In a Rhyme Duel, Hint (⌘I) now lists up to six rhymes at once instead of one, and the model keeps ten behind each of its lines instead of six, so a second press has others to show.
- **Add-a-Word remembers the story.** Each new sentence goes to the model with the sentences before it written out in full, not only as the words you traded one at a time, so the model carries the story on, and scores each sentence for how much sense it makes there.
- **Games in your language.** With another language than English in Settings › Prompt, every game is played in it: the model's lines, words, categories, and reasons, with the drawn stories and topics still keeping games fresh. Rhymes don't mind accents (“rád” answers “hrad”), Word Football chains “kůň” to a word starting with N, and Longest Word spends č as c.
- **Restart a game with ⌘R.** Restart in a game's actions (⌘K) starts it over from the beginning while you're still playing; the game so far goes to Recent Chats. Once a round is over, ⌘R is still Play Again.

### Ask

- **Buttons with nothing to add fade further.** The selection, clipboard, and screenshot buttons above the window go much fainter when there is nothing they could add, so a glance tells which of them a click would do something with.
- **Quoted text opens in full.** The text a question went with, quoted above it, now says how many words it is, and when its two lines cut it short, a click on its header shows all of it and folds it back. Handy after copying a few long messages to ask about together. The card under the input offers its chevron only when its three lines really leave something out.

### Privacy

- **Reopening a chat keeps its time.** A chat you reopen from Recent Chats comes back with the time it had left, instead of another 30 minutes. A message or a click on the timer still gives it 30 minutes again.
- **The timer warns you.** In a chat's last 5 minutes, the capsule under the window's bottom right turns pink, so a chat you still need doesn't go by surprise. Click it for another 30 minutes.

### Fixes

- ⌘C copies again in the window, a torn-off answer, and Settings, and ⌘X, ⌘A, and ⌘Z work there too. The window takes the keyboard without making Meraline the app in front, and the shortcuts never reached the text.
- A game's name in the footer stays gray, as the provider's does, instead of turning pink on your move. The clock's Forgotten capsule now reads like the mode toggle's chosen segment, a pink clock with the word in black.
- Meraline no longer freezes when an update it found finishes downloading while the window is hidden. The shortcut then did nothing, and neither did opening the app, until it was force quit. The capsule under the window changes its label from Update Available to Restart to Update in place now, instead of fading one capsule into another, which macOS 27 never finished laying out.

## v1.6.0 - 2026-09-27

### Ask

- **Answers read like documents.** Headings, lists, quotes, and tables show as they should, and code sits in a box with its language and a Copy button. Actions (⌘K) adds Copy Code Block for each block of code in the last answer.
- **Tear off an answer.** Tear Off Answer (⌘T) in Actions keeps an answer on screen in a small glass note beside the window, so a recipe or a list of steps stays in view while you work in another app. Drag it by its header or any empty space, resize it from its sides and bottom, and fold its question away with the chevron. It floats above other apps on every Space until its cross or Esc puts it away, and nothing of it is saved.

![An answer with its commands in code boxes, and the same answer torn off into a floating note beside the window](https://raw.githubusercontent.com/Meldiron/meraline/v1.6.0/docs/screenshots/note-light.png)

- **Ask Again with another provider.** Actions (⌘K) offers Ask Again with each of your other ready providers, and the one you pick answers your follow-ups too. Handy when one model turns a question down.

### Agents

- **Agents hand you files.** When Claude Code, Codex, or OpenCode makes a file for you, a report, a chart, a spreadsheet, it hands it over with Meraline's own `present_files` tool, and the file shows under the answer with its icon, kind, and size. A picture shows itself instead of its icon; click it to see it larger. Open it in its app, show it in Finder, copy it, save it to Downloads, or drag it anywhere. Actions (⌘K) offers the same, with ⌘O to open and ⌘S to save. Files stay in the chat's folder until you save or copy them, and Open never runs an app or a script.

![Claude Code hands over the app icon, shown as a picture, and a Markdown note, each with Open, Show in Finder, Copy, and Save to Downloads](https://raw.githubusercontent.com/Meldiron/meraline/v1.6.0/docs/screenshots/files-light.png)

- **Agents answer sooner.** Claude Code and Codex stay running for the chat, so a follow-up doesn't start them over, and they start as soon as the shortcut opens the window in Agent mode. Codex writes its answer word by word instead of all at once.
- **A cleared folder doesn't stop the agent.** macOS clears old files out of its temporary folder. If it cleared a chat's folder, Meraline makes a new one, the agent carries on, and a warning under your question says the earlier files are gone.

### Privacy

- **Every chat has 30 minutes.** A capsule under the window's bottom right says how long the open chat has left, in minutes and then, in its last minute, seconds. Each message starts its 30 minutes over, and so does a click on the capsule. When the time runs out, the chat is deleted from memory with the files its agent worked on; whatever you'd typed stays in the input. Recent Chats no longer stops at your last five: a chat you close keeps counting down there, reopening it starts its time over, and an answer still arriving is never cut off. This replaces Settings › General › Start a new chat and the countdown on the pin.

![An answer about selected text, with 30 min left in a capsule under the window's bottom right](https://raw.githubusercontent.com/Meldiron/meraline/v1.6.0/docs/screenshots/panel-light.png)

- **Limits on what chats hold.** A chat holds up to 512 MB, pictures mostly, and a question that doesn't fit stays in the input and says why. Meraline keeps up to 1,000 chats, and an agent's folder for a chat takes in up to 20,000 files and folders from what you attach.
- **Permissions in one place.** Settings › Permissions lists what Meraline can ask macOS for, Accessibility and Screen Recording, with the features each one turns on and whether macOS allows it right now. Allow… asks macOS for it, and Open System Settings goes straight to the list with Meraline's switch. General no longer repeats the Accessibility row, and `meraline://settings?pane=permissions` opens the pane.

![Settings › Permissions: Accessibility and Screen Recording, what each turns on, and whether macOS allows it](https://raw.githubusercontent.com/Meldiron/meraline/v1.6.0/docs/screenshots/permissions-light.png)

- **No more "on this Mac" label.** The badge beside the mode toggle and the note in the sparkle's panel are gone. Apple Intelligence and local Ollama models still answer without your question leaving the Mac.

### Diagnostics

- **More in Copy Diagnostics.** The report says what the chats hold: how many there are and the memory they take, when the next one goes, the agents' folders on disk and their size, and how many agents are running, in counts and sizes only. It also says whether Meraline has Screen Recording access.

### Fixes

- Dragging an empty part of the window moves it again on macOS 27, where the window had stopped moving.

## v1.5.0 - 2026-09-26

### Ask

- **Rewrite an answer.** Actions (⌘K) under an answer now offer Make Shorter, Make Longer, Make Simpler, Make More Concrete, and Turn into Bullet List. The new answer replaces the old one under the same question, so rewrites stack (shorter, then a list) and a follow-up builds on what you see. If you stop the rewrite, or it fails, the old answer comes back.
- **Insert the answer where you were.** Press ⌘↵ under an answer, or pick Insert Answer from Actions (⌘K), and the window closes and pastes the answer at the cursor of the app you opened it over. Select a paragraph, press ⌥ Space, ask for it friendlier, press ⌘↵, and the new text replaces the old. Your clipboard is put back afterwards. While you type a follow-up, ⌘↵ leaves it alone. Pasting needs the same Accessibility access as reading a selection; without it, the answer is copied for you to paste.

![The chat's actions over an answer: Insert Answer into TextEdit, Copy Conversation, Ask Again, and the five rewrites](https://raw.githubusercontent.com/Meldiron/meraline/v1.5.0/docs/screenshots/actions-light.png)

- **Ask an agent why.** When Claude Code asks to write a file, run a command, or use a skill, **Why?** beside Deny and Allow has it say in one line why it wants to, from your chat and what it is about to do. The reason comes from a quick run of Claude Code's small model with no tools, in a few seconds, and goes when you answer.

![Claude Code asks to write notes.md, and under Deny and Allow its one-line reason from Why?](https://raw.githubusercontent.com/Meldiron/meraline/v1.5.0/docs/screenshots/agent-light.png)

- **More to automate.** `meraline://ask` takes `clipboard=1` and `screen=1`, which add the clipboard and a screenshot as the buttons above the window do, so a Shortcut can ask "What's wrong here?" about your screen in one step. With `send=1` the question waits for the screenshot. `agent=1` or `agent=0` picks the mode for the question. `meraline://play?game=oddOneOut` starts a game (`meraline://play` alone shows them all), and `meraline://mode?agent=1` switches to Agent.

### Privacy

- **See when a chat moves on.** A pinned window left on screen now counts down on its pin, "forgets in 28m", to the moment its chat moves to Recent Chats and the next question starts fresh. An anonymous chat is forgotten. Come back to the window and the clock stops. The clock now runs while a pinned window sits in the background as well as while the window is hidden, and it moves the chat on at that moment instead of the next time the window opens. Settings › General › Privacy sets how long, or Never.
- **On this Mac.** While Apple Intelligence answers, or Ollama with a model on this Mac, a quiet "on this Mac" sits beside the mode toggle, and the sparkle's panel says the same under those providers. Ollama's cloud models, a server on another machine, and Custom servers don't get it, since what you ask leaves the Mac.
- **Hide from screen sharing.** Turn it on in the sparkle's panel or Settings › General › Privacy, and Meraline asks macOS to leave the window out of screen sharing, recordings, and screenshots. A crossed-out eye beside the mode toggle shows it's on. It's off unless you turn it on. Apps that record the whole display, such as QuickTime and some video-call apps, can still show the window, so try it with yours before a call where it matters.

![An answer from Apple Intelligence with on this Mac beside the mode toggle, and the pin counting down to a fresh start](https://raw.githubusercontent.com/Meldiron/meraline/v1.5.0/docs/screenshots/privacy-light.png)

### Updates and diagnostics

- **Updates under the window.** What's New moves from beside the pin to a capsule under the window's bottom left, lined up with the buttons above it. When a new version is out, an Update Available capsule sits beside it, or Restart to Update once the update has downloaded. Each has a cross that hides it until the next update.
- **Screenshots in What's New.** The release notes in the window now show the pictures the release shows on GitHub. Click one to open it full size.
- **Copy Diagnostics after a crash.** If Meraline quits unexpectedly, the next time you open the window a Copy Diagnostics capsule under it copies a report of what went wrong to paste into a bug report: the error and where in the code it happened, read from the crash report macOS keeps, with no questions, answers, or keys. It shows once for each crash, and its cross hides it. Nothing is sent anywhere.

### Fixes

- Claude Code's asks no longer turn themselves down a few seconds after they appear ("tool permission stream closed"). The card now waits for as long as you take.

## v1.4.0 - 2026-09-26

### Ask

- **Ask about what you select.** Select text in any app and press ⌥Space, then click the text cursor above the window, or press ⇧⌘E, and the text arrives in a glass card above the mode toggle, with the app it came from, ready for a question, or just press Return. Nothing you select joins a question until you add it. The chevron shows all of it, and the cross or ⌫ in an empty input leaves it out. A sent question keeps it as a quiet quote above it. **Files work too:** with files or folders selected in Finder, the shortcut attaches them, photos in either mode and everything else when you ask an agent, and ⌫ in an empty input takes out the last one. Only what is selected when you press the shortcut comes along: let go of a selection and the next press leaves it out. Meraline needs Accessibility access to read the selection and says so in the window until you allow it; Settings › General turns the feature off. Most apps share their selection directly, and in the few that don't, such as browsers and Zed, Meraline uses the app's own Copy command, or ⌘C, and puts your clipboard back. Without Accessibility access, **Services › Ask Meraline** in any app does the same, and `meraline://ask?selection=…` hands text over from Shortcuts or a script.
- **Add the clipboard or the screen.** Beside the text cursor, two more buttons add context in one click. The clipboard (⇧⌘V) brings whatever you copied: text arrives in a card like a selection, a copied picture or file is attached as if you had pasted it. The screen (⇧⌘S) attaches a screenshot of the display the window is on, taken without Meraline's own window in it, so the model sees what you were looking at. Screenshots need Screen Recording access; the first time, a capsule beside the buttons offers to ask for it. Nothing is recorded: one picture is taken when you click, and it lives in memory with the chat.
- **Context adds up.** Each of the three buttons adds what it has now, so one question can carry text selected in two apps, a couple of copies, and a screenshot of each app you opened the window over. Click a button again while that same text, copy, or screenshot is in your question and it comes out again. A faded button has nothing to add, a plain one adds, and a pink one is already in your question. A password copied from a password manager is never read.

![Meraline answering a question about selected text: the text quoted above the question, the selection, clipboard, and screenshot buttons above the window, and Copy Answer and Actions in the footer](https://raw.githubusercontent.com/Meldiron/meraline/v1.4.0/docs/screenshots/panel-light.png)

- **Agents read any file.** Drop a PDF, a spreadsheet, or any other file into the window, or copy it in Finder and press ⌘V, and the agent finds it in the chat's workspace, where it stays for follow-up questions. LLMs still take images only: a file dropped while you ask an LLM waits under the input with a Switch to Agent button, instead of being turned away as not an image.
- **Ask a project.** Drop a folder and ask about it. The agent works on a copy in the chat's workspace, never on your folder, and the copy stays for follow-ups until the chat leaves Recent Chats. A folder in git brings the files git keeps and its history, but not what git ignores, so a project with gigabytes of dependencies and builds copies in a second or two.
- **Actions, the way Raycast does them.** The footer under an answer offers one action, Copy Answer (⇧⌘C), and **Actions** (⌘K) for the rest, in a panel you can search and work from the keyboard: Copy Conversation, **Ask Again** (⌘R) for a fresh answer from the provider you're on now, New Chat, **Show Agent's Files in Finder** (⇧⌘O) for an agent's chat, and **Delete Chat** (⇧⌘⌫), which asks first and keeps the chat out of Recent Chats. A game's panel has Hint, Play Again, Copy Game, End Game, and Delete Game. The sparkle opens the same kind of panel, with the providers of the mode you're in, the other mode, anonymous mode, and Settings.
- **Recent chats under the input.** A clock beside the games shows how many of your last five chats are kept. Click it for the same kind of panel: pick a chat to reopen it, or Clear Recent Chats, which asks first. Shaking the window while you drag it clears them too. Either way the count rolls to zero and the clock says so.

![The recent chats in a panel above the clock under the input, with Clear Recent Chats and a search field](https://raw.githubusercontent.com/Meldiron/meraline/v1.4.0/docs/screenshots/menu-light.png)

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

![The eight games unfolded from the controller under the input, with a round of Odd One Out on](https://raw.githubusercontent.com/Meldiron/meraline/v1.4.0/docs/screenshots/game-light.png)


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
