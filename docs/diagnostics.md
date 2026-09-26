# Diagnostics and logging

Meraline logs through one surface, `Log`, so every event has a category and can be filtered from the command line, Console.app, or the diagnostics report. Messages describe what happened: which provider, which model, which path, which error. They never contain a question, an answer, or a key.

## Getting a report from a user

Settings › About › **Copy Diagnostics** puts a Markdown report on the clipboard. It contains:

- Meraline version and build, macOS version, and whether the app runs as Apple silicon or Intel code.
- Where the app is installed, with the home folder shortened to `~`, and a note if it runs from a disk image or Downloads (the usual reason updates and the login item misbehave).
- Settings: the mode (LLM or Agent) and the default provider of each, shortcut, window behavior, whether the system prompt was customized, and update settings and state.
- One row per provider: ready, no key, not ready, or off; the model; the endpoint host, or the resolved path of the command-line tool and how many of its MCP servers a question may use (counts, never names). Never the key.
- The last 300 log entries.

The bug report template asks for it. `Diagnostics.report` builds it and `DiagnosticsTests` checks that an injected key never appears.

## Categories

| Category | What it records |
| --- | --- |
| `app` | Launch, updates from an earlier version, `meraline://` routes, diagnostics copied |
| `panel` | Reserved for window events |
| `chat` | A question sent (provider, model, turn, image count), an answer finished, stopped, or failed; a workspace made for the chat; an agent's ask (the tool by name, never its input) and whether it was allowed, denied, or answered. For games: a game started, each move sent, kept on this Mac, or sent back, and each round over, by game name and turn number only |
| `providers` | HTTP failures from a provider, with the status code |
| `cli` | Command-line tools resolved and run, with the executable path, exit status, whether they ran in the chat's workspace, and how many MCP servers were allowed; an agent's MCP servers listed, or why listing them failed |
| `updates` | Sparkle: started, channel, found, staged, installing, skipped, errors |
| `settings` | The mode or a mode's default provider changing; an agent's MCP server turned on or off in Settings, by name |

## Watching live

```sh
log stream --predicate 'subsystem == "com.meldiron.meraline"' --level info
log stream --predicate 'subsystem == "com.meldiron.meraline" && category == "cli"'
```

`scripts/dev_run.sh` also captures the app's stdout and stderr in `/tmp/meraline.log`.

## Adding a log line

```swift
Log.chat.info("Asking \(provider.name) (\(model))")
Log.updates.error("Update check failed: \(error.localizedDescription)")
```

Pick the category that matches the subsystem, keep the message free of user content, and prefer one line per event over a running commentary. Everything goes to the unified log as public text and into the in-memory buffer, so the rule about content is what keeps the report safe to paste.
