# Diagnostics and logging

Meraline logs through one surface, `Log`, so every event has a category and can be filtered from the command line, Console.app, or the diagnostics report. Messages describe what happened: which provider, which model, which path, which error. They never contain a question, an answer, or a key.

## Getting a report from a user

Settings › About › **Copy Diagnostics** puts a Markdown report on the clipboard. So does **Copy Diagnostics** in the sparkle's panel, at any time, even mid-chat; the capsule under the card says Copied for a moment. It contains:

- Meraline version and build, macOS version, and whether the app runs as Apple silicon or Intel code.
- Where the app is installed, with the home folder shortened to `~`, and a note if it runs from a disk image or Downloads (the usual reason updates and the login item misbehave).
- After a crash, a Crash section (see below).
- Settings: the mode (LLM or Agent) and the default provider of each, shortcut and whether Meraline could register it, window behavior and whether the window hides from screen sharing, whether the shortcut brings the selected text and whether Meraline has Accessibility access, whether it has Screen Recording access, which prompts were changed in Settings › Prompt (by name, never their text), and update settings and state.
- One row per provider: ready, no key, not ready, or off; the model; the endpoint host, or the resolved path of the command-line tool and how many of its MCP servers a question may use (counts, never names). Never the key.
- Storage, in counts and sizes only: the open chat's turns and how many recent chats there are, the memory they take and the largest chat's against its 512 MB, when the next chat's time runs out, this run's workspaces (folders, files and folders in them, their size, and the fullest against its 20,000), the workspace folders of other Meraline processes, and how many agents are running. `Diagnostics.storage(of:)` walks the workspaces off the main thread.
- The last 300 log entries.

Before it is copied, the whole report goes through `Diagnostics.redacting`: the home folder becomes `~` wherever it appears, the log's paths included, and any API key set in Settings is replaced with `[key]`, in case one ever reached an error description. The bug report template asks for it. `Diagnostics.report` builds it, and `DiagnosticsTests` checks that an injected key and the home folder never appear, and that diagnostics copied mid-chat hold none of its questions, answers, or selected text.

## After a crash

When Meraline quits unexpectedly, macOS writes a crash report to `~/Library/Logs/DiagnosticReports` (and later moves it to `Retired` there). At launch, `CrashNotice` looks for a Meraline report (`bug_type` 309, Meraline's bundle identifier) newer than the previous launch, whose date is the only thing it keeps in UserDefaults. If it finds one, a **Copy Diagnostics** capsule under the card copies the report above, says Copied, and goes; its cross hides it, and the next launch never offers the same crash again. For the rest of that run, Settings › About and the sparkle's panel include the crash too. Both the capsule and the sparkle's row copy through `CrashNotice.copyDiagnostics(of:preferences:updates:)`, and the sparkle's copy shows the same capsule saying Copied, never a second one. Nothing is sent anywhere.

`CrashReport` reads macOS's report and keeps only what says how and where Meraline crashed:

- Version and build, when it crashed and how long after launching.
- The exception type, signal, and subtype, and the termination with the reasons macOS gives (a missing library, a code signature), the home folder shortened to `~`.
- The Swift runtime's message up to its first colon, and none of it if it quotes something (`Duplicate values for key: '…'` keeps `Duplicate values for key`), or an uncaught Objective-C exception's name, never its reason. Those are the parts that could hold a value.
- Meraline's image UUID and load address, and up to 40 frames of the crashed thread, and of the last exception backtrace for an uncaught exception, in macOS's own layout. A release strips its symbols, so Meraline's frames show `0x<load address> + <offset>`; read them with the release's `Meraline-<version>-dSYMs.zip`, for example `atos -arch arm64 -o Meraline.app.dSYM/Contents/Resources/DWARF/Meraline -l <load address> <address>`.

It leaves out everything else in the report: registers, memory, other threads, and the identifiers of the Mac. The log of the run that crashed is gone with it, since the log lives in memory; the report says so, and its log is this run's. `CrashReportTests` checks that a quoted value, an exception's reason, and the report's identifiers never appear.

## Categories

| Category | What it records |
| --- | --- |
| `app` | Launch, a crash found since the previous launch (its version and exception type) and whether its diagnostics were copied or hidden, updates from an earlier version, the first-launch shortcut picker (whether the shortcut looked taken and by which of the apps it looks for, what it suggested, and what was kept or chosen), `meraline://` routes and Services › Ask Meraline, Accessibility access asked for, granted, or withdrawn, Screen Recording access asked for, and granted or withdrawn while Settings › Permissions is open, System Settings opened from Settings › Permissions, diagnostics copied (after a crash, from the panel, or from Settings) |
| `panel` | How the selection was read when the shortcut opened the window (through Accessibility, or with the app's Copy command) and its length or how many files, never the text or the file names; whether the selection button added or took out the offered text; what the clipboard button added (text and its length, an image, or how many files) and whether the screenshot button took its picture or took one out, never what either showed; Insert Answer (the app it pasted into, how, and the answer's length, or why it only copied); the window closed after losing the keyboard, and why (a click or key press elsewhere, another Space, a window of Meraline's), or kept after losing it with nothing pressed, with the name of the app in front; the panel warmed up; a preset put in or sent; a shake; never what is typed |
| `chat` | A question sent (provider, model, turn, image and file counts), an answer finished, stopped, or failed; a workspace made for the chat, or made again after it went missing; a chat given more time, a chat or recent chats whose time ran out, and a question kept back at the chat's memory limit; an agent's ask (the tool by name, never its input) and whether it was allowed, denied, or answered; a rewrite asked for (which one), stopped, or failed; Improve asked for on the Context card (provider, model, how many questions, from which stage), the text given back as it was from a stage and the next one asked for, the text improved (the stage, how many edits), given back as it was through every stage, undone, or failed, never the text; an agent's reason for its ask shown (Why?), never the reason; anonymous mode turned on or off. For games: a game started, each move sent, kept on this Mac, or sent back, and each round over, by game name and turn number only |
| `providers` | HTTP failures from a provider, with the status code |
| `cli` | Command-line tools resolved and run, with the executable path, exit status, whether they ran in the chat's workspace, how many attachments were copied in (for a folder, how many files git keeps in it, or that it was outside git), and how many MCP servers were allowed; an agent's MCP servers listed, or why listing them failed; Claude Code asked why it asks (the tool by name) |
| `updates` | Sparkle: started, channel, found, staged, installing, skipped, errors |
| `settings` | The mode or a mode's default provider changing; an agent's MCP server turned on or off in Settings, by name; Hide from Screen Sharing turned on or off |

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
