# Meraline

A tiny macOS utility for ephemeral LLM chats. Press a shortcut, ask a question, read the answer, ask a follow-up if you need one. Close the window and the conversation is gone. Nothing is written to disk.

## Features

- Floating Liquid Glass window that opens with a global shortcut (default `⌥Space`)
- Streaming answers from Anthropic, OpenAI, Google Gemini, OpenRouter, Ollama, or any OpenAI-compatible server
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

Updates are published as GitHub releases. The appcast lives at `https://github.com/Meldiron/meraline/releases/latest/download/appcast.xml`, and the EdDSA public key is set in `project.yml`. The matching private key is stored in the release machine's Keychain by Sparkle's `generate_keys`.

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Archive and export the app:
   ```sh
   xcodegen generate
   xcodebuild -project Meraline.xcodeproj -scheme Meraline -configuration Release -archivePath build/Meraline.xcarchive archive
   mkdir -p build/release
   ditto -c -k --sequesterRsrc --keepParent build/Meraline.xcarchive/Products/Applications/Meraline.app build/release/Meraline-<version>.zip
   ```
3. Generate the appcast with Sparkle's tool (it lives in the resolved Sparkle package under `SourcePackages/artifacts/sparkle/Sparkle/bin`):
   ```sh
   generate_appcast --download-url-prefix https://github.com/Meldiron/meraline/releases/download/v<version>/ build/release
   ```
4. Create the release and attach both files:
   ```sh
   gh release create v<version> build/release/Meraline-<version>.zip build/release/appcast.xml
   ```

Builds are signed ad hoc. For distribution to other Macs, sign with a Developer ID certificate and notarize the archive.
