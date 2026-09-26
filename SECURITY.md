# Security Policy

## Supported versions

The latest release on the [Releases](https://github.com/Meldiron/meraline/releases) page is supported. Installed copies update themselves, so there are no maintained older lines.

## Reporting a vulnerability

Report suspected vulnerabilities privately through GitHub's private vulnerability reporting:

**https://github.com/Meldiron/meraline/security/advisories/new**

Do not open a public issue or pull request for a suspected vulnerability. Include what the flaw is, how to reproduce it, which version of Meraline and macOS you used, and a suggested fix if you have one. You will get an acknowledgement within five business days. If the report is confirmed, a fix ships as a regular release as soon as it is ready and the details are published afterwards.

## Scope

This policy covers the Meraline app in this repository. Vulnerabilities in the AI providers Meraline talks to, or in the command-line tools it runs (Claude Code, Codex, OpenCode), belong with their maintainers, though a private heads-up here is welcome.

## Security-relevant behavior

- **API keys live in the Keychain.** They are stored as generic passwords under the service `com.meldiron.meraline.api-keys`, one item per provider, and are never written to preferences, logs, or diagnostics.
- **Nothing is written to disk.** Conversations, games, drafts, pasted images, and recent chats exist only in memory and are gone when Meraline quits.
- **Requests carry the minimum.** OpenAI requests ask not to be stored (`store: false`). Gemini keys travel in a header, never in a URL. Every HTTP session is ephemeral, with no cookie or cache storage.
- **Command-line tools run contained.** Claude Code, Codex, and OpenCode are launched in an empty temporary folder made for the chat and removed with it or at quit, without session persistence. Claude Code's file tools work in that folder and every write is asked about first; Codex's sandbox allows writes only there and in the temporary folders, with the network off for commands; OpenCode turns down whatever its permissions would ask about. An agent may use the MCP servers you set up in it, with whatever access you gave them there; Settings › Agents lists them, as the agent reports them, and turns any of them off for Meraline alone. Meraline names the servers it allows on each run and never edits an agent's MCP configuration.
- **Logs and diagnostics are private by default.** The in-app log records events, providers, models, and error descriptions, never questions, answers, or keys. The diagnostics report from Settings › About is built from that log and from non-secret settings, so it is safe to paste into an issue.
- **Releases are signed, hardened, and notarized, and the artifact is what gets checked.** Every release build is exported with a Developer ID certificate, runs under the hardened runtime, and is notarized and stapled, both the app and the disk image. The release pipeline reads the finished artifacts, nested Sparkle helpers included, and fails if any of this is missing.
- **Downloads can be traced to their build.** Release files carry a Sigstore build-provenance attestation binding them to the tag and workflow run that produced them (`gh attestation verify Meraline-<version>.dmg --repo Meldiron/meraline`), and `SHA256SUMS.txt` is published alongside them. Updates are verified separately by Sparkle with an EdDSA signature.
- **No sandbox.** Meraline is not App Sandboxed, because it needs to run command-line tools from your `PATH`. Notarization does not require the sandbox.

See [docs/releasing.md](docs/releasing.md) for how the release pipeline enforces the signing guarantees, and [docs/diagnostics.md](docs/diagnostics.md) for exactly what a diagnostics report contains.
