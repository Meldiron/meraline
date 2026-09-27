#!/bin/zsh
# Captures the README screenshots, in dark and light:
#
#   panel     an answered question about selected text in LLM mode, with the buttons above the window and the
#             mode toggle, the controller, and the clock under the input
#   actions   the chat's panel of actions (⌘K) over that answer: Insert Answer into TextEdit and the rewrites
#   game      Odd One Out after the model's first move, with its choice buttons and the games unfolded
#   menu      the panel of recent chats behind the clock, with the chat asked for the panel shot in it
#   note      an answer with code in it, and the same answer torn off into a floating note beside the window
#   agent     Agent mode: an answer, its trail of MCP tools, and a request to write a file with its Why?
#   question  Agent mode: a question from the agent with its choices
#   files     Agent mode: the files an agent handed over, a picture with its preview and a Markdown file
#   settings  Settings on the Claude Code page, with its MCP servers
#   permissions  Settings › Permissions
#
# It stays out of the way of the copy you use. A throwaway Debug build runs in front of a full-screen
# gradient backdrop, so nothing else on the screen can appear, and keeps its settings in a defaults suite
# of its own (MERALINE_DEFAULTS_SUITE, which only Debug builds read). It is driven through meraline://
# URLs and a few mouse presses: keep your hands off the Mac while it runs, a few minutes. With
# --wait-idle it first waits until the Mac has been idle for two minutes (MERALINE_SHOT_IDLE seconds) with
# the screen unlocked, and it
# keeps the display awake while it works, since a locked screen can't be captured.
#
# The LLM shots ask a real provider: MERALINE_SHOT_LLM (a Provider raw value, default openRouter) with its
# key from the Keychain and MERALINE_SHOT_MODEL (default: the model you set for it). The agent shots run
# scripts/lib/screenshots/demo-agent.sh as the Claude Code command, a stand-in that speaks Claude Code's
# protocol with scripted demo MCP servers and answers, so no picture shows your own servers or files. The
# actions shot puts a blank TextEdit document in front, behind the backdrop, and closes TextEdit after if it
# wasn't open.
#
#   scripts/screenshots.sh [--wait-idle] [dark|light|both] [output directory]
#
# MERALINE_SHOT_ONLY="settings agent" takes only the named pictures.
#
# Needs Screen Recording and Accessibility permission for the terminal that runs it.

# No errexit: zsh skips the EXIT trap when errexit fires inside a function. Failures return from main
# (err_return) and cleanup runs after it, whatever happened.
set -uo pipefail

wait_idle=0
[[ ${1:-} == --wait-idle ]] && { wait_idle=1; shift; }
appearances=(${1:-both})
[[ $appearances == both ]] && appearances=(dark light)
out=${2:-docs/screenshots}
llm=${MERALINE_SHOT_LLM:-openRouter}
only=${MERALINE_SHOT_ONLY:-}
wants() { [[ -z $only || " $only " == *" $1 "* ]]; }
model=${MERALINE_SHOT_MODEL:-$(defaults read com.meldiron.meraline "$llm.model" 2>/dev/null || true)}

here=${0:A:h}
repo=${here:h}
cd "$repo"
mkdir -p "$out"
derived="$repo/build/DerivedData-screenshots"
app=${MERALINE_SHOT_APP:-$derived/Build/Products/Debug/Meraline.app}
binary="$app/Contents/MacOS/Meraline"

if [[ -z ${MERALINE_SHOT_APP:-} ]]; then
  echo "==> Building a Debug copy"
  source "$here/lib/signing.sh"
  xcodegen generate --quiet
  rm -rf "$derived/Build"
  pretty_xcodebuild build/logs/screenshots.log -project Meraline.xcodeproj -scheme Meraline -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$derived" -clonedSourcePackagesDirPath "$repo/build/SourcePackages" \
    $(adhoc_signing_flags) build
fi
[[ -x $binary ]] || { echo "No app at $app." >&2; exit 1; }

tools=$(mktemp -d)
for tool in windows press backdrop; do
  swiftc -O -o "$tools/$tool" "$here/lib/screenshots/$tool.swift" 2>/dev/null
done
window() { "$tools/windows" "$@" 2>/dev/null || true; }

# The stand-in agent lives at a short, neutral path, since Settings shows the command.
demo=/tmp/meraline-demo
mkdir -p $demo
cp "$here/lib/screenshots/demo-agent.sh" $demo/claude
chmod +x $demo/claude
# The picture the demo agent hands over for the files shot: Meraline's own icon.
for icon in "$app/Contents/Resources/AppIcon.icns" /Applications/Meraline.app/Contents/Resources/AppIcon.icns; do
  [[ -f $icon ]] && sips -s format png -Z 1024 "$icon" --out $demo/icon.png >/dev/null 2>&1 && break
done

# The throwaway copy can write the Settings window's frame to the shared preferences; put it back after.
frame_key="NSWindow Frame MeralineSettings"
saved_frame=$(defaults read com.meldiron.meraline "$frame_key" 2>/dev/null || true)
read -r screen_w screen_h <<< "$(window screen)"

suites=(com.meldiron.meraline.screenshots.llm com.meldiron.meraline.screenshots.agent)
pid="" backdrop="" logger=""
textedit_was_open=0
pgrep -xq TextEdit && textedit_was_open=1
cleanup() {
  for p in $pid $backdrop $logger; do kill $p 2>/dev/null || true; done
  if (( ! textedit_was_open )) && pgrep -xq TextEdit; then
    osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1 || true
  fi
  for suite in $suites; do defaults delete $suite >/dev/null 2>&1 || true; done
  if [[ -n $saved_frame ]]; then defaults write com.meldiron.meraline "$frame_key" "$saved_frame"
  else defaults delete com.meldiron.meraline "$frame_key" >/dev/null 2>&1 || true; fi
  rm -rf $tools $demo
}
trap 'cleanup; exit 130' INT TERM

idle_seconds() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
screen_locked() {
  ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers xml1 -o - - 2>/dev/null \
    | grep -A1 CGSSessionScreenIsLocked | grep -q '<true/>'
}

prepare() {  # suite key type value ...
  local suite=$1; shift
  defaults delete $suite >/dev/null 2>&1 || true
  defaults write $suite isPinned -bool true
  defaults write $suite placement -string screenCenter
  while (( $# )); do defaults write $suite "$1" "-$2" "$3"; shift 3; done
}

# (Re)starts the backdrop in front of every other window: "above" keeps it over normal windows for the
# panel shots; "normal" lets Settings open over it.
backdrop_up() {  # appearance above|normal
  [[ -n $backdrop ]] && kill $backdrop 2>/dev/null
  "$tools/backdrop" $1 $2 &
  backdrop=$!
  sleep 1
}

# Moves the pointer to a corner of the backdrop, so no tooltip shows up in a picture.
park() { "$tools/press" move $(( screen_w - 12 )) $(( screen_h - 12 )); sleep 0.3; }

# Clicks the first button of the throwaway copy whose title starts with $1, found through Accessibility.
click() { "$tools/press" button $pid "$1"; }

# Puts a blank TextEdit document in front, behind the backdrop: the app Insert Answer offers to paste into,
# and a way to leave the window without the keyboard, as clicking another app does.
textedit_front() {
  osascript -e 'tell application "TextEdit"' -e 'make new document' -e 'activate' -e 'end tell' >/dev/null 2>&1
  sleep 1
}

launch() {  # suite appearance
  local args=(-hasLaunchedBefore NO -hasChosenShortcut YES -SUEnableAutomaticChecks NO)
  [[ $2 == light ]] && args+=(-NSRequiresAquaSystemAppearance YES)
  MERALINE_DEFAULTS_SUITE=$1 "$binary" "${args[@]}" >/dev/null 2>&1 &
  pid=$!
  logfile=$(mktemp)
  marker=0
  /usr/bin/log stream --process $pid --info --style compact > $logfile 2>/dev/null &
  logger=$!
  for _ in {1..40}; do
    bounds=$(window $pid panel)
    [[ -n $bounds ]] && break
    sleep 0.25
  done
  [[ -n ${bounds:-} ]] || { echo "The panel never appeared." >&2; return 1; }
  sleep 1
}

quit() {
  kill $pid $logger 2>/dev/null || true
  rm -rf "${TMPDIR%/}/Meraline/Workspaces/$pid"
  pid="" logger=""
  sleep 1
}

# Waits for a log line written after the last action, so an earlier line never counts twice.
marker=0
mark() { marker=$(wc -l < $logfile); }
since_mark() { sed -n "$(( marker + 1 )),\$p" $logfile; }
wait_for() {  # pattern seconds
  for _ in $(seq $(( $2 * 2 ))); do
    since_mark | grep -q -E "$1" && return 0
    sleep 0.5
  done
  echo "Timed out waiting for: $1" >&2
  tail -5 $logfile >&2
  return 1
}

url() { mark; open -a "$app" "$1"; }
encode() { python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
ask() { url "meraline://ask?text=$(encode "$1")&send=1"; }
ask_about() { url "meraline://ask?selection=$(encode "$1")&text=$(encode "$2")&send=1"; }  # selection question
shoot_panel() {  # name [minimum height]
  wants $1 || return 0
  read -r x y w h <<< "$(window $pid panel)"
  local height=$(( h > ${2:-0} ? h : ${2:-0} ))
  screencapture -x -R "$x,$y,$w,$height" "$out/$1$suffix.png"
  echo "    $1$suffix.png"
}

main() {
setopt local_options err_return
if (( wait_idle )); then
  local quiet=${MERALINE_SHOT_IDLE:-120}
  echo "==> Waiting until the Mac has been idle for $quiet seconds, with the screen unlocked"
  until (( $(idle_seconds) >= quiet )) && ! screen_locked; do sleep 2; done
fi
# Keep the display awake (and so the screen unlocked) until this script ends.
caffeinate -d -w $$ &

for appearance in $appearances; do
  screen_locked && { echo "The screen is locked; stopping." >&2; return 1; }
  suffix=""
  [[ $appearance == light ]] && suffix="-light"
  echo "==> $appearance"
  backdrop_up $appearance above
  park

  if wants panel || wants actions || wants game || wants menu; then
  # LLM mode, with a real provider.
  prepare ${suites[1]} mode string llm provider string $llm claudeCode.enabled bool false
  [[ -n $model ]] && defaults write ${suites[1]} "$llm.model" -string "$model"
  launch ${suites[1]} $appearance
  ask_about "A cortado is espresso cut with about the same amount of warm milk, which puts it between a macchiato and a flat white." "How is this different from a latte?"
  wait_for 'Answer (complete|failed)' 120
  since_mark | grep -q 'Answer complete' || { echo "The LLM did not answer." >&2; return 1; }
  sleep 1.5
  shoot_panel panel

  # The chat's actions, with TextEdit in front for Insert Answer; the same click puts them away.
  if wants actions; then
    textedit_front
    click Actions
    park
    sleep 1
    shoot_panel actions
    click Actions
    sleep 1.2
  fi

  # Odd One Out: the controller (588 points from the window's left, 127 below its top) unfolds the games to
  # its left, and its button is the fifth of eight, 130 points left of the games capsule's right edge.
  read -r x y w h <<< "$(window $pid panel)"
  "$tools/press" $(( x + 588 )) $(( y + 127 )) 0.1
  sleep 0.8
  mark
  "$tools/press" $(( x + 474 )) $(( y + 127 )) 0.1
  park
  for attempt in 1 2 3; do
    wait_for 'Odd One Out: the model (moved|.s move failed|.s reply sent)' 90 || true
    since_mark | grep -q 'Odd One Out: the model moved' && break
    url "meraline://ask?send=1"
  done
  sleep 1.5
  shoot_panel game

  # The recent chats behind the clock at the row's right end: a click opens their panel inside the window,
  # which grows when the panel reaches below the card. The chat asked above is in there by now.
  "$tools/press" $(( x + 636 )) $(( y + 127 )) 0.1
  park
  sleep 0.8
  shoot_panel menu
  quit
  fi

  # An answer with code, torn off into a note beside the window through the chat's actions.
  if wants note; then
  backdrop_up $appearance above
  prepare ${suites[1]} mode string llm provider string $llm claudeCode.enabled bool false
  [[ -n $model ]] && defaults write ${suites[1]} "$llm.model" -string "$model"
  launch ${suites[1]} $appearance
  ask "How do I find which app is using port 3000 on my Mac, and stop it? Keep it short: a sentence or two and the commands."
  wait_for 'Answer (complete|failed)' 120
  since_mark | grep -q 'Answer complete' || { echo "The LLM did not answer." >&2; return 1; }
  sleep 1.5
  click Actions
  sleep 1
  click "Tear Off Answer"
  park
  sleep 1.5
  read -r x y w h <<< "$(window $pid panel)"
  read -r nx ny nw nh <<< "$(window $pid note)"
  [[ -n ${nx:-} ]] || { echo "The note never appeared." >&2; return 1; }
  local left=$(( x < nx ? x : nx )) top=$(( y < ny ? y : ny ))
  local right=$(( x + w > nx + nw ? x + w : nx + nw )) bottom=$(( y + h > ny + nh ? y + h : ny + nh ))
  screencapture -x -R "$left,$top,$(( right - left )),$(( bottom - top ))" "$out/note$suffix.png"
  echo "    note$suffix.png"
  quit
  fi

  # Agent mode, with the demo stand-in as Claude Code.
  backdrop_up $appearance above
  prepare ${suites[2]} mode string agent provider string claudeCode claudeCode.enabled bool true claudeCode.baseURL string $demo/claude
  launch ${suites[2]} $appearance
  wait_for 'Claude Code lists [0-9]+ MCP server' 30
  if wants agent || wants question; then
  ask "Which open issues mention the menu bar icon? Save a summary to notes.md."
  wait_for 'Agent asks for leave' 60
  sleep 1.2
  mark
  click "Why?"
  park
  wait_for "Agent's reason for its ask shown" 30
  sleep 1
  shoot_panel agent

  url "meraline://new"
  sleep 1
  ask "Draft a changelog entry for the next release."
  wait_for 'Agent asks a question' 60
  sleep 1.2
  shoot_panel question
  fi

  if wants files; then
  url "meraline://new"
  sleep 1
  ask "Export the app icon at 1024 pixels for the press kit, with a short note on where each size goes."
  wait_for 'Answer complete' 60
  sleep 1.5
  shoot_panel files
  fi

  backdrop_up $appearance normal
  url "meraline://settings?pane=claudeCode"
  for _ in {1..40}; do
    settings=$(window $pid settings)
    [[ -n $settings ]] && break
    sleep 0.25
  done
  [[ -n ${settings:-} ]] || { echo "The Settings window never appeared." >&2; return 1; }
  sleep 1.5
  read -r id sx sy sw sh <<< "$settings"
  [[ -n ${MERALINE_SHOT_DEBUG:-} ]] && screencapture -x -l $id "$MERALINE_SHOT_DEBUG/settings-opened$suffix.png"
  # Click the selected Claude Code row, which puts the focus in the sidebar, then scroll the page down to
  # its MCP servers.
  "$tools/press" $(( sx + 107 )) $(( sy + 520 )) 0.1
  "$tools/press" scroll $(( sx + 480 )) $(( sy + 300 )) 1200
  park
  sleep 1
  if wants settings; then
    screencapture -x -l $id "$out/settings$suffix.png"
    echo "    settings$suffix.png"
  fi
  if wants permissions; then
    url "meraline://settings?pane=permissions"
    sleep 1.5
    # Past the pane's header, so both permissions show.
    "$tools/press" scroll $(( sx + 480 )) $(( sy + 300 )) 170
    park
    sleep 0.5
    screencapture -x -l $id "$out/permissions$suffix.png"
    echo "    permissions$suffix.png"
  fi
  quit

  kill $backdrop 2>/dev/null || true
  backdrop=""
  sleep 0.5
done
}

main
result=$?
cleanup
if (( result == 0 )); then echo "==> Done. Look at every picture before committing it."; else echo "==> Failed." >&2; fi
exit $result
