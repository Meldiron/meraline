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
  <a href="https://github.com/Meldiron/meraline/actions/workflows/tests.yml"><img src="https://github.com/Meldiron/meraline/actions/workflows/tests.yml/badge.svg" alt="Tests"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-8E6CF0" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Swift-6-F89BCD" alt="Swift 6">
</p>

---

Meraline is a tiny Mac app for quick questions. Press <kbd>⌥</kbd> <kbd>Space</kbd>, type, and the answer streams in a small glass window. Ask a follow-up if you need one. Press <kbd>Esc</kbd> and it's gone.

There are no chat lists, no history, and no projects. Nothing is saved to disk, and the next question starts fresh.

## What it does

✨ **Opens anywhere.** A global shortcut brings up the window over whatever you're doing, on any Space or full-screen app. It doesn't steal focus from the app you're in.

💬 **Answers quickly.** Replies stream in as they're written, with bold, italics, code, and links rendered.

🖼️ **Understands images.** Paste a screenshot or drop an image into the window and ask about it.

🔌 **Uses the AI you already have.** Click the sparkle in the window to switch between the providers you've turned on.

| | Works with |
| --- | --- |
| **API keys** | Anthropic, OpenAI, Google Gemini, OpenRouter |
| **Local models** | Ollama, LM Studio, or any OpenAI-compatible server |
| **Command-line agents** | Claude Code, Codex, OpenCode, using the account they're signed in to |

🔒 **Stays private.** API keys live in your Keychain. Conversations exist only in memory. OpenAI requests ask not to be stored, and command-line agents run in an empty temporary folder without saving a session.

⚙️ **Feels at home on a Mac.** Settings look like System Settings, the icon follows light and dark mode, and updates install themselves.

## Getting started

1. Download the latest `Meraline-<version>.zip` from [Releases](https://github.com/Meldiron/meraline/releases/latest).
2. Unzip it and drag **Meraline** into your Applications folder.
3. Open it. A sparkle appears in your menu bar, and the window opens so you can try it.
4. Click the gear button (or press <kbd>⌘</kbd> <kbd>,</kbd>) and connect a provider: paste an API key, or turn on Ollama, Claude Code, Codex, or OpenCode.

That's it. Press <kbd>⌥</kbd> <kbd>Space</kbd> whenever you have a question.

## Keyboard shortcuts

| Shortcut | What it does |
| --- | --- |
| <kbd>⌥</kbd> <kbd>Space</kbd> | Open or close Meraline (change it in Settings) |
| <kbd>↩</kbd> or <kbd>⇥</kbd> | Send |
| <kbd>Esc</kbd> | Stop the answer, clear what you typed, or close the window |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>C</kbd> | Copy the last answer |
| <kbd>⌘</kbd> <kbd>N</kbd> | Start a new chat |
| <kbd>⌘</kbd> <kbd>,</kbd> | Open Settings |

## Build it yourself

You'll need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/Meldiron/meraline.git
cd meraline
xcodegen generate
open Meraline.xcodeproj
```

Run the tests from Xcode, or with:

```sh
xcodebuild -project Meraline.xcodeproj -scheme Meraline test
```

To also check the command-line agents installed on your Mac, set `TEST_RUNNER_MERALINE_CLI_E2E=1` before running the tests.

## For maintainers

Every push to `main` and every pull request runs the tests in GitHub Actions.

To ship a new version, push a tag:

```sh
git tag v1.0.1
git push origin v1.0.1
```

The Release workflow builds the app with the tag's version, signs it with the Developer ID certificate, notarizes it, signs the update for [Sparkle](https://sparkle-project.org), and publishes a GitHub release with `Meraline-<version>.zip` and `appcast.xml`. Installed copies check `https://github.com/Meldiron/meraline/releases/latest/download/appcast.xml` for updates.

The workflow needs these repository secrets:

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_P12` | Base64 of the exported Developer ID Application certificate and private key (`.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password chosen when exporting the `.p12` |
| `NOTARY_KEY` | Contents of an App Store Connect API key (`AuthKey_XXXX.p8`) |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The App Store Connect issuer ID |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key from Sparkle's `generate_keys -x` |
