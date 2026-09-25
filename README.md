# Meraline

A tiny macOS utility for ephemeral LLM chats. Press a shortcut, ask a question, read the answer, ask a follow-up if you need one. Close the window and the conversation is gone. Nothing is written to disk.

## Features

- Floating Liquid Glass window that opens with a global shortcut (default `⌥Space`)
- Streaming answers from Anthropic, OpenAI, Google Gemini, OpenRouter, Ollama, or any OpenAI-compatible server
- Answers from command-line agents you're already signed in to: Claude Code (`claude`), Codex (`codex`), and OpenCode (`opencode`). They run in an empty temporary folder with tools off (Claude Code) or a read-only sandbox (Codex), and nothing is saved as a session.
- Paste or drop images into the question
- API keys stored in the macOS Keychain; requests use an ephemeral URL session and ask OpenAI not to store responses
- Settings styled after System Settings
- Automatic updates through [Sparkle](https://sparkle-project.org)

Requires macOS 26 or later.

## Keyboard

| Key | Action |
| --- | --- |
| `⌥Space` | Open or close Meraline (change it in Settings) |
| `↩` | Send |
| `Esc` | Stop answering, clear the question, or close |
| `⇧⌘C` | Copy the last answer |
| `⌘N` | Start a new chat |
| `⌘,` | Settings |

## Build

Meraline uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```sh
brew install xcodegen
xcodegen generate
open Meraline.xcodeproj
```

Run the tests with:

```sh
xcodebuild -project Meraline.xcodeproj -scheme Meraline test
```

## Releasing an update

Every push to `main` and every pull request runs the tests in GitHub Actions.

To ship a version, push a tag:

```sh
git tag v1.0.1
git push origin v1.0.1
```

The Release workflow builds the app with the tag's version, signs it with the Developer ID certificate, notarizes and staples it, signs the update for Sparkle, and publishes a GitHub release with `Meraline-<version>.zip` and `appcast.xml`. Installed copies find the update through `https://github.com/Meldiron/meraline/releases/latest/download/appcast.xml`.

The workflow needs these repository secrets:

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_P12` | Base64 of the exported Developer ID Application certificate and private key (`.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password chosen when exporting the `.p12` |
| `NOTARY_KEY` | Contents of an App Store Connect API key (`AuthKey_XXXX.p8`) |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The App Store Connect issuer ID |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key from Sparkle's `generate_keys -x` |
