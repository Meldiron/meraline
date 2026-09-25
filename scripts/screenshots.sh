#!/bin/zsh
# Captures the README screenshots: the panel with an answer, the sparkle menu, and Settings.
#
# It starts a second, throwaway copy of a built Meraline.app whose preferences are overridden on the
# command line (nothing is written to disk), asks it a question through the meraline:// URL scheme,
# and screenshots the windows in front of a full-screen gradient backdrop, so nothing else on the
# screen (windows, desktop icons, wallpaper) ends up in the pictures. The copy you normally run is
# left alone. Keep your hands off the mouse and keyboard while it runs (about a minute).
#
#   scripts/screenshots.sh [dark|light] [path/to/Meraline.app] [output directory]
#
# Environment: MERALINE_SHOT_QUESTION, MERALINE_SHOT_PROVIDER (a Provider raw value, default claudeCode).
# Needs Screen Recording and Accessibility permission for the terminal that runs it.

set -euo pipefail

appearance=${1:-dark}
app=${2:-build/DerivedData/Build/Products/Release/Meraline.app}
out=${3:-docs/screenshots}
question=${MERALINE_SHOT_QUESTION:-"What's the difference between a flat white and a latte?"}
provider=${MERALINE_SHOT_PROVIDER:-claudeCode}
suffix=""
[[ $appearance == light ]] && suffix="-light"

[[ $app == /* ]] || app="$PWD/$app"
binary="$app/Contents/MacOS/Meraline"
[[ -x $binary ]] || { echo "No app at $app. Build it first." >&2; exit 1; }
mkdir -p "$out"

# Three tiny helpers, compiled once per run: list windows, press the mouse, and draw the backdrop.
here=${0:A:h}
tools=$(mktemp -d)
for tool in windows press backdrop; do
  swiftc -O -o "$tools/$tool" "$here/lib/screenshots/$tool.swift" 2>/dev/null
done
window() { "$tools/windows" "$1" "$2" 2>/dev/null || true; }

cleanup() {
  for p in ${pid:-} ${backdrop:-} ${logger:-}; do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT

"$tools/backdrop" "$appearance" &
backdrop=$!
sleep 1

# Argument-domain defaults override the saved ones for this process only.
args=(-hasLaunchedBefore NO -isPinned YES -provider "$provider" -placement screenCenter)
[[ $appearance == light ]] && args+=(-NSRequiresAquaSystemAppearance YES)
"$binary" "${args[@]}" >/dev/null 2>&1 &
pid=$!

for _ in {1..40}; do
  bounds=$(window "$pid" panel)
  [[ -n $bounds ]] && break
  sleep 0.25
done
[[ -n ${bounds:-} ]] || { echo "The panel never appeared." >&2; exit 1; }
sleep 1

# The app logs "Answer complete" (or failed, or stopped) when a turn ends; that is the signal to capture.
logfile=$(mktemp)
/usr/bin/log stream --process "$pid" --info --style compact > "$logfile" 2>/dev/null &
logger=$!
sleep 1

# The URL scheme reaches this instance because -a names the exact bundle it runs from.
encoded=$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$question")
open -a "$app" "meraline://ask?text=${encoded}&send=1"
for _ in {1..240}; do
  grep -q -E 'Answer (complete|failed|stopped)' "$logfile" && break
  sleep 0.5
done
grep -q 'Answer complete' "$logfile" || { echo "No answer arrived:" >&2; tail -5 "$logfile" >&2; exit 1; }
sleep 1.5

read -r x y w h <<< "$(window "$pid" panel)"
screencapture -x -R "$x,$y,$w,$h" "$out/panel$suffix.png"
echo "panel$suffix.png ($w×$h points)"

# The sparkle's centre: 32 margin + 20 padding + half of its 28-point frame from the left, 62 points down.
# Holding the mouse button keeps the menu open while the screenshot is taken.
"$tools/press" $((x + 66)) $((y + 62)) 2.5 &
sleep 1.2
# Same height as the panel, unless the answer was short and the menu hangs below it.
screencapture -x -R "$x,$y,$w,$(( h > 340 ? h : 340 ))" "$out/menu$suffix.png"
wait $! 2>/dev/null || true
sleep 0.5
echo "menu$suffix.png"

# Settings, on the Apple Intelligence page (the first row under Providers in the sidebar).
open -a "$app" "meraline://settings"
for _ in {1..40}; do
  settings=$(window "$pid" settings)
  [[ -n $settings ]] && break
  sleep 0.25
done
[[ -n ${settings:-} ]] || { echo "The Settings window never appeared." >&2; exit 1; }
sleep 1
read -r id sx sy sw sh <<< "$settings"
"$tools/press" $((sx + 107)) $((sy + 264)) 0.1
sleep 1.2
screencapture -x -l "$id" "$out/settings$suffix.png"
echo "settings$suffix.png"
