#!/bin/bash
# Takes pictures of Meraline without taking over the Mac: the real panel and Settings window, built in the
# test host with scripted state (ShowcaseTests), put behind every other window over the screenshots' gradient,
# and captured with ScreenCaptureKit, so their glass looks as it does on screen. Nothing is clicked or typed,
# and it runs while you work. Each picture waits until the keyboard and mouse have been still for 5 seconds,
# then takes the keyboard for about a second, since a window draws its active look only while it has it.
#
# Usage: scripts/showcase.sh [dark|light|both] [picture ...] [--out directory]
#
#   opening       Rhyme Duel waiting for its first move: the invitation card with Random Rhyme
#   longest-word  Longest Word once the model has picked its word: the nine letters in glass bubbles
#   usage         Settings › Usage over the last 30 days, from made-up counts (MeralineTests/DemoUsage.swift)
#   usage-games   further down the same page: the games played, and a section for each
#   prompt        Settings › Prompt: the language, and the LLMs' and the agents' instructions
#   prompt-games  further down the same page: the games, one of them changed, and Why?
#   follow-ups    an answer about DNS with three follow-ups under it
#   presets       the presets above an empty chat, Fix Grammar put in the input for a text selected in Mail
#   preset-text   Fix Grammar put in the input with nothing to work on: the Context card open under it with the keyboard
#   prompt-presets  Settings › Prompt › Presets: the four defaults and one of your own
#   software-update  Settings › Software Update on a beta: its channel chip and the switch for beta updates
#   cost-nudge    the empty panel with what LLMs and agents have cost today
#   preview       Agent mode: a page and a Markdown file an agent handed over, each with its preview strip
#   note-stack    three answers torn off into one note: the last in front, the edges of the other two under it
#   decision      Decision mode: Jev's Yes about a text selected in Mail, with how sure it is
#   decision-levels  Decision mode: a priority placed along Low, Medium, and High, and the answers under the input
#   decision-lines  Decision mode about each line: six tasks from Notes under Yes, No, and Not sure, Yes open and the rest folded
#   decision-models  Settings › Decision Models: the three providers in the sidebar, and Ollama's pane turned on with Nimble and what to pull
#
# Pictures go to docs/screenshots, as name.png (dark) and name-light.png, the names the README uses. Pictures
# that need a real provider, an agent, or clicks come from scripts/screenshots.sh. Needs Screen Recording
# permission for Meraline, which the test host is.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
. "$SCRIPT_DIR/lib/signing.sh"
cd "$PROJECT_DIR"

APPEARANCE=both
ONLY=()
OUT="$PROJECT_DIR/docs/screenshots"
while [ $# -gt 0 ]; do
    case "$1" in
        dark|light|both) APPEARANCE="$1"; shift ;;
        --out) OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2 ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) ONLY+=("$1"); shift ;;
    esac
done

echo "==> Generating Meraline.xcodeproj"
xcodegen generate --quiet

echo "==> Taking pictures into ${OUT#"$PROJECT_DIR"/}"
mkdir -p "$PROJECT_DIR/build/logs"
# xcodebuild hands the test host the variables that start with TEST_RUNNER_, without the prefix.
export TEST_RUNNER_MERALINE_SHOWCASE="$OUT"
export TEST_RUNNER_MERALINE_SHOWCASE_APPEARANCE="$APPEARANCE"
export TEST_RUNNER_MERALINE_SHOWCASE_ONLY="${ONLY[*]:-}"
# English and the US region, so numbers read 1,284 and 12.9K whatever this Mac's region is.
# shellcheck disable=SC2046
xcodebuild -project Meraline.xcodeproj -scheme Meraline -destination 'platform=macOS' \
    -derivedDataPath "$PROJECT_DIR/build/DerivedData-showcase" \
    -clonedSourcePackagesDirPath "$PROJECT_DIR/build/SourcePackages" \
    -testLanguage en -testRegion US \
    $(adhoc_signing_flags) test -only-testing:MeralineTests/ShowcaseTests 2>&1 \
    | tee "$PROJECT_DIR/build/logs/showcase.log" \
    | grep --line-buffered -E '^Showcase: |error:|✘|recorded an issue|\*\* TEST (SUCCEEDED|FAILED)' \
    | sed -u 's/^Showcase: /    /'
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then echo "==> Done. Look at every picture before committing it."; else echo "==> Failed; see build/logs/showcase.log." >&2; fi
exit "$status"
