#!/bin/bash
# Records clips of Meraline's animations without taking over the Mac, the way scripts/showcase.sh takes pictures:
# the real panel, built in the test host with scripted state (ClipTests), put behind every other window over the
# screenshots' gradient, and recorded with ScreenCaptureKit at up to 60 frames a second while the scene runs.
# Nothing is clicked or typed. Each clip waits until the keyboard and mouse have been still for 5 seconds, then
# the window has the keyboard for the clip's few seconds, since it draws its active look only while it has it.
#
# Usage: scripts/clips.sh [dark|light|both] [clip ...] [--out directory] [--backdrop picture.png]
#
#   open-close    the window opening on an empty chat and closing again, as ⌥ Space does
#   ask           a question sent: the conversation appears, the answer streams in, the follow-ups come, and Esc starts a new chat
#   what-changed  Show What Changed on a grammar fix, and Show Answer back
#   live          the Live decisions demo for the promo's film: a reply to Nora typed badly, the capsules turning red,
#                 typed again and turning green as it grows, a question kept, and Return
#
# With --backdrop, the picture (the promo's public/backdrop-night.png) covers the whole screen behind the panel, which
# sits where the promo's films have it, and the films' 16:9 region is recorded, with the scene's markers written to
# name.json beside the clip, so it drops straight into the promo project.
#
# Clips go to build/clips unless --out says where, as name.mp4 (dark) and name-light.mp4. To judge a change to an
# animation, record a set before it and one after, and put them side by side:
#   ffmpeg -i before/ask.mp4 -i after/ask.mp4 -filter_complex hstack ask.mp4
# Needs Screen Recording permission for Meraline, which the test host is.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
. "$SCRIPT_DIR/lib/signing.sh"
cd "$PROJECT_DIR"

APPEARANCE=dark
ONLY=()
OUT="$PROJECT_DIR/build/clips"
BACKDROP=""
while [ $# -gt 0 ]; do
    case "$1" in
        dark|light|both) APPEARANCE="$1"; shift ;;
        --out) OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2 ;;
        --backdrop) BACKDROP="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) ONLY+=("$1"); shift ;;
    esac
done

echo "==> Generating Meraline.xcodeproj"
xcodegen generate --quiet

echo "==> Recording clips into ${OUT#"$PROJECT_DIR"/}"
mkdir -p "$PROJECT_DIR/build/logs"
# xcodebuild hands the test host the variables that start with TEST_RUNNER_, without the prefix.
export TEST_RUNNER_MERALINE_CLIPS="$OUT"
export TEST_RUNNER_MERALINE_SHOWCASE_APPEARANCE="$APPEARANCE"
export TEST_RUNNER_MERALINE_CLIPS_ONLY="${ONLY[*]:-}"
export TEST_RUNNER_MERALINE_CLIP_BACKDROP="$BACKDROP"
# shellcheck disable=SC2046
xcodebuild -project Meraline.xcodeproj -scheme Meraline -destination 'platform=macOS' \
    -derivedDataPath "$PROJECT_DIR/build/DerivedData-clips" \
    -clonedSourcePackagesDirPath "$PROJECT_DIR/build/SourcePackages" \
    -testLanguage en -testRegion US \
    $(adhoc_signing_flags) test -only-testing:MeralineTests/ClipTests 2>&1 \
    | tee "$PROJECT_DIR/build/logs/clips.log" \
    | grep --line-buffered -E '^Clip: |error:|✘|recorded an issue|\*\* TEST (SUCCEEDED|FAILED)' \
    | sed -u 's/^Clip: /    /'
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then echo "==> Done."; else echo "==> Failed; see build/logs/clips.log." >&2; fi
exit "$status"
