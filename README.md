<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/icon-dark.png">
    <img src="docs/icon-light.png" width="160" alt="Meraline app icon: a smiling sparkle">
  </picture>
</p>

<h1 align="center">Meraline</h1>

<p align="center">
  <strong>Ask AI anything, right where you are. Then let it go.</strong>
</p>

<p align="center">
  <a href="https://github.com/Meldiron/meraline/actions/workflows/ci.yml"><img src="https://github.com/Meldiron/meraline/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-8E6CF0" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Swift-6-F89BCD" alt="Swift 6">
</p>

---

Meraline is a tiny Mac app for quick questions. Press <kbd>⌥</kbd> <kbd>Space</kbd>, type, and the answer streams in a small glass window. Ask a follow-up if you need one. Click away and it waits for you; press <kbd>Esc</kbd> to start fresh. Leave it hidden for half an hour and the next question starts a fresh chat on its own.

There are no chat lists, no history, and no projects. Nothing is saved to disk. Pin the window (📌 or <kbd>⌘</kbd> <kbd>P</kbd>) to keep it open while you work in other apps.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel.png">
    <img src="docs/screenshots/panel-light.png" width="704" alt="Meraline's floating glass panel showing a question and a streamed answer">
  </picture>
</p>

## What it does

✨ **Opens anywhere.** A global shortcut brings up the window over whatever you're doing, on any Space or full-screen app. It doesn't steal focus from the app you're in.

💬 **Answers quickly.** Replies stream in as they're written, with bold, italics, code, and links rendered. While a model searches the web or runs a tool, you see what it's doing. While it thinks, Meraline murmurs ("sharpening pencils…", "asking the void…", "consulting the sparkle council…").

🖼️ **Understands images.** Paste a screenshot or drop an image into the window and ask about it.

🎲 **Plays word games.** The sparkle menu's Play section has six quick games against the model: Rhyme Duel, Add-a-Word, Categories, Word Football, Odd One Out, and Fix the Typo. The model moves first, a move that breaks the rules comes back to you instead of costing a turn, and <kbd>Esc</kbd> forgets the game like any other chat.

🍎 **Works out of the box.** On a Mac with Apple Intelligence, the on-device model built into macOS answers the moment you install. No key, no account, and nothing leaves your Mac.

🔌 **Uses the AI you already have.** Click the sparkle in the window to switch between the providers you've turned on, start a game, or reopen one of your last five chats. Recent chats stay in memory until you quit Meraline.

| | Works with |
| --- | --- |
| **On this Mac** | Apple Intelligence, the on-device model in macOS 26 |
| **API keys** | Anthropic, OpenAI, Google Gemini, OpenRouter |
| **Local models** | Ollama, LM Studio, or any OpenAI-compatible server |
| **Command-line agents** | Claude Code, Codex, OpenCode, using the account they're signed in to |

🔒 **Stays private.** API keys live in your Keychain. Conversations exist only in memory. OpenAI requests ask not to be stored, and command-line agents run in an empty temporary folder without saving a session. When you do want to keep something, copy the answer or the whole conversation as Markdown.

⚙️ **Feels at home on a Mac.** Settings look like System Settings, the icon follows light and dark mode, and updates install themselves.

<table align="center">
  <tr>
    <td align="center">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/menu.png">
        <img src="docs/screenshots/menu-light.png" width="440" alt="The sparkle menu listing the providers that are turned on and the recent chats">
      </picture>
    </td>
    <td align="center">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings.png">
        <img src="docs/screenshots/settings-light.png" width="440" alt="Settings window on the Apple Intelligence provider page">
      </picture>
    </td>
  </tr>
  <tr>
    <td align="center"><sub>Switch providers or reopen a recent chat from the sparkle</sub></td>
    <td align="center"><sub>Settings look like System Settings</sub></td>
  </tr>
</table>

## Getting started

With [Homebrew](https://brew.sh):

```sh
brew install --cask meldiron/tap/meraline
```

Or download the latest `Meraline-<version>.dmg` from [Releases](https://github.com/Meldiron/meraline/releases/latest), open it, and drag **Meraline** into your Applications folder.

Then open Meraline. A sparkle appears in your menu bar, and the window opens so you can try it. On a Mac with Apple Intelligence turned on, you can ask a question right away. For other models, click the gear button (or press <kbd>⌘</kbd> <kbd>,</kbd>) and connect a provider: paste an API key, or turn on Ollama, Claude Code, Codex, or OpenCode.

That's it. Press <kbd>⌥</kbd> <kbd>Space</kbd> whenever you have a question.

> [!TIP]
> ChatGPT, Gemini, Copilot, and Raycast also use <kbd>⌥</kbd> <kbd>Space</kbd> by default, and macOS quietly gives the shortcut to whichever app grabbed it last. If Meraline doesn't open, pick another shortcut in **Settings › General**, such as <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>Space</kbd>.

## Keyboard shortcuts

| Shortcut | What it does |
| --- | --- |
| <kbd>⌥</kbd> <kbd>Space</kbd> | Open or close Meraline (change it in Settings) |
| <kbd>↩</kbd> or <kbd>⇥</kbd> | Send |
| <kbd>Esc</kbd> | Stop the answer, then start a new chat, then close the window |
| <kbd>⌘</kbd> <kbd>P</kbd> | Pin or unpin the window |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>C</kbd> | Copy the last answer |
| <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>C</kbd> | Copy the whole conversation as Markdown |
| <kbd>⌘</kbd> <kbd>N</kbd> | Start a new chat |
| <kbd>⌘</kbd> <kbd>,</kbd> | Open Settings |

## Privacy, and how to check it

Meraline is built so you don't have to take its word for any of this.

- **No account and no server in between.** Questions go straight from your Mac to the provider you chose. Meraline has no backend, no analytics, and no crash reporting. The only other connection is a once-a-day update check against `github.com`, which you can turn off in Settings. Watch the traffic with any network monitor and you'll see nothing else.
- **Nothing on disk.** Conversations and games live in memory and are gone when you quit. The preferences file (`defaults read com.meldiron.meraline`) holds settings only: shortcut, window placement, and which providers are on.
- **Keys in the Keychain.** API keys are stored as Keychain items under the service `com.meldiron.meraline.api-keys`, where Keychain Access can show and delete them. They never appear in preferences, logs, or diagnostics.
- **Command-line agents stay in charge of their own sign-in.** Meraline runs the unmodified `claude`, `codex`, and `opencode` commands in an empty temporary folder that is deleted afterwards, with session persistence off. It never reads or copies their tokens.
- **On-device means on-device.** Apple Intelligence answers come from the model inside macOS. Nothing is sent anywhere.
- **It's all open source.** Search the code for `URLSession`, `Process`, and `Keychain` to see every place Meraline talks to anything.

## Automate it

Other apps and scripts can open Meraline through the `meraline://` URL scheme, which makes it easy to wire up in Shortcuts, Raycast, or a shell alias:

| URL | What it does |
| --- | --- |
| `meraline://ask?text=…` | Opens the window with the question filled in |
| `meraline://ask?text=…&send=1` | Fills it in and sends it |
| `meraline://new` | Starts a new chat and opens the window |
| `meraline://settings` | Opens Settings |

```sh
open "meraline://ask?text=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' 'Explain CRDTs in one paragraph')&send=1"
```

## Updates and beta builds

Meraline checks for updates once a day and installs them quietly in the background; the menu bar menu and Settings › Software Update show when one is ready. To try builds before they are released, switch **Settings › Software Update › Update channel** to Beta. After an update, Meraline shows what changed.

Something off? **Settings › About › Copy Diagnostics** gives you a report to paste into a [bug report](https://github.com/Meldiron/meraline/issues/new?template=bug_report.yml). It has no keys, questions, or answers in it.

## Build it yourself

You'll need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). No Apple Developer account is needed to build and run.

```sh
brew install xcodegen
git clone https://github.com/Meldiron/meraline.git
cd meraline
scripts/dev_run.sh     # build and launch
scripts/test.sh        # run the tests (add --e2e to also run the installed command-line agents)
```

`xcodegen generate` followed by `open Meraline.xcodeproj` gets you into Xcode. [CONTRIBUTING.md](CONTRIBUTING.md) has the rest; Meraline is [MIT licensed](LICENSE).

## For maintainers

Every push to `main` and every pull request runs the tests in GitHub Actions and builds a preview of the installer, attached to the run as an artifact.

To ship a new version, push a tag:

```sh
git tag v1.0.1
git push origin v1.0.1
```

The Release workflow runs `scripts/release.sh`: it builds the app with the tag's version, signs it with the Developer ID certificate, notarizes and staples it, wraps it in a styled disk image that is signed and notarized in its own right, signs the update for [Sparkle](https://sparkle-project.org), and publishes a GitHub release with the `.dmg`, the `.zip`, `appcast.xml`, debug symbols, and checksums. Installed copies check `https://github.com/Meldiron/meraline/releases/latest/download/appcast.xml` for updates once a day.

Release notes come from `CHANGELOG.md` when the version has an entry there, and from the commits since the previous tag otherwise.

[docs/releasing.md](docs/releasing.md) covers the pipeline step by step, the disk image design and how to edit it, running a release on your own Mac, and the secrets the workflow needs.
