#!/bin/zsh
# Captures the README screenshots, in dark and light:
#
#   panel     an answered question in LLM mode, with the mode toggle and the games under the input
#   game      Odd One Out after the model's first move, with its choice buttons
#   menu      the sparkle menu: the providers of the current mode and Recent Chats
#   agent     Agent mode: an answer, its trail of MCP tools, and a request to write a file
#   question  Agent mode: a question from the agent with its choices
#   settings  Settings on the Claude Code page, with its MCP servers
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
# protocol with scripted demo MCP servers and answers, so no picture shows your own servers or files.
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

# The throwaway copy can write the Settings window's frame to the shared preferences; put it back after.
frame_key="NSWindow Frame MeralineSettings"
saved_frame=$(defaults read com.meldiron.meraline "$frame_key" 2>/dev/null || true)
read -r screen_w screen_h <<< "$(window screen)"

suites=(com.meldiron.meraline.screenshots.llm com.meldiron.meraline.screenshots.agent)
pid="" backdrop="" logger=""
cleanup() {
  for p in $pid $backdrop $logger; do kill $p 2>/dev/null || true; done
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

launch() {  # suite appearance
  local args=(-hasLaunchedBefore NO -SUEnableAutomaticChecks NO)
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
ask() { url "meraline://ask?text=$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$1")&send=1"; }
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

  if wants panel || wants game || wants menu; then
  # LLM mode, with a real provider.
  prepare ${suites[1]} mode string llm provider string $llm claudeCode.enabled bool false
  [[ -n $model ]] && defaults write ${suites[1]} "$llm.model" -string "$model"
  launch ${suites[1]} $appearance
  ask "What's the difference between a flat white and a latte?"
  wait_for 'Answer (complete|failed)' 120
  since_mark | grep -q 'Answer complete' || { echo "The LLM did not answer." >&2; return 1; }
  sleep 1.5
  shoot_panel panel

  # Odd One Out: its button is the fifth of six in the games group, 107 points below the window's top.
  read -r x y w h <<< "$(window $pid panel)"
  mark
  "$tools/press" $(( x + 619 )) $(( y + 107 )) 0.1
  park
  for attempt in 1 2 3; do
    wait_for 'Odd One Out: the model (moved|.s move failed|.s reply sent)' 90 || true
    since_mark | grep -q 'Odd One Out: the model moved' && break
    url "meraline://ask?send=1"
  done
  sleep 1.5
  shoot_panel game

  # The sparkle menu, held open by a long press. The chat asked above is in Recent Chats by now.
  "$tools/press" $(( x + 66 )) $(( y + 62 )) 2.5 &
  sleep 1.2
  shoot_panel menu 420
  wait $! 2>/dev/null || true
  park
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
  shoot_panel agent

  url "meraline://new"
  sleep 1
  ask "Draft a changelog entry for the next release."
  wait_for 'Agent asks a question' 60
  sleep 1.2
  shoot_panel question
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
