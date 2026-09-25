#!/bin/bash
# Checks a Meraline disk image the way a download gets used: mounts it, confirms the Finder
# layout matches the contract in scripts/lib/dmg.sh, and verifies the app inside it.
#
# Usage: scripts/verify_dmg.sh <Meraline.dmg> [--require any|developer-id|notarized]
#
# The level is passed through to scripts/verify_app.sh for both the image and the app it holds.
# Reading the saved icon positions straight out of .DS_Store is what catches a returning scroll
# bar: only the app and the Applications link may have one.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/dmg.sh
. "$SCRIPT_DIR/lib/dmg.sh"

DMG=""
REQUIRE="any"
while [ $# -gt 0 ]; do
    case "$1" in
        --require) REQUIRE="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) DMG="$1"; shift ;;
    esac
done
if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
    echo "usage: $0 <Meraline.dmg> [--require any|developer-id|notarized]" >&2
    exit 2
fi
LABEL="$(basename "$DMG")"

FAILURES=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1" >&2; FAILURES=$((FAILURES + 1)); }

echo "==> Verifying $LABEL (--require $REQUIRE)"

# The image itself carries a signature and a notarization ticket of its own; Gatekeeper judges
# it before the user ever sees what is inside.
if [ "$REQUIRE" != "any" ]; then
    "$SCRIPT_DIR/verify_app.sh" "$DMG" --require "$REQUIRE"
fi

MOUNT_POINT="$(mktemp -d)"
detach() {
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap detach EXIT
hdiutil attach "$DMG" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -noautoopen -quiet

VOLUME="$(diskutil info -plist "$MOUNT_POINT" | plutil -extract VolumeName raw - 2>/dev/null || true)"
if [ "$VOLUME" = "$DMG_VOLUME_NAME" ]; then
    pass "volume is named $VOLUME"
else
    fail "volume is named \"$VOLUME\", expected \"$DMG_VOLUME_NAME\""
fi

APP="$MOUNT_POINT/Meraline.app"
[ -d "$APP" ] && pass "contains Meraline.app" || fail "Meraline.app is missing from the image"

if [ -L "$MOUNT_POINT/Applications" ] && [ "$(readlink "$MOUNT_POINT/Applications")" = "/Applications" ]; then
    pass "Applications links to /Applications"
else
    fail "Applications is not a symlink to /Applications"
fi

[ -f "$MOUNT_POINT/.background.tiff" ] && pass "background image present" || fail "no .background.tiff at the volume root"
[ -f "$MOUNT_POINT/.VolumeIcon.icns" ] && pass "volume icon present" || fail "no .VolumeIcon.icns at the volume root"

if [ -f "$MOUNT_POINT/.DS_Store" ]; then
    VENV="$(dmg_python_env "$PROJECT_DIR")"
    if LAYOUT="$("$VENV/bin/python" - "$MOUNT_POINT/.DS_Store" "Meraline.app" \
        "$DMG_WINDOW_W" "$DMG_WINDOW_H" "$DMG_ICON_SIZE" "$DMG_TEXT_SIZE" \
        "$DMG_APP_X" "$DMG_DROP_X" "$DMG_ICON_Y" <<'PY'
import plistlib, re, struct, sys
from ds_store import DSStore

path, app_name = sys.argv[1], sys.argv[2]
window_w, window_h, icon_size, text_size, app_x, drop_x, icon_y = (int(v) for v in sys.argv[3:10])

def as_plist(value):
    return value if isinstance(value, dict) else plistlib.loads(bytes(value))

def as_point(value):
    if isinstance(value, (bytes, bytearray)):
        return struct.unpack(">II", bytes(value[:8]))
    return (int(value[0]), int(value[1]))

positions, window, view = {}, {}, {}
with DSStore.open(path, "r") as store:
    for entry in store:
        if entry.code == b"Iloc":
            positions[entry.filename] = as_point(entry.value)
        elif entry.filename == "." and entry.code == b"bwsp":
            window = as_plist(entry.value)
        elif entry.filename == "." and entry.code == b"icvp":
            view = as_plist(entry.value)

problems = []
expected = {app_name: (app_x, icon_y), "Applications": (drop_x, icon_y)}
if positions != expected:
    problems.append(f"icon positions are {positions}, expected {expected}")

bounds = re.match(r"\{\{(-?\d+), (-?\d+)\}, \{(\d+), (\d+)\}\}", str(window.get("WindowBounds", "")))
if not bounds or (int(bounds[3]), int(bounds[4])) != (window_w, window_h):
    problems.append(f"window bounds are {window.get('WindowBounds')!r}, expected {window_w}x{window_h}")
for key in ("ShowStatusBar", "ShowToolbar", "ShowPathbar", "ShowSidebar"):
    if window.get(key):
        problems.append(f"{key} is on")
if int(view.get("iconSize", 0)) != icon_size:
    problems.append(f"icon size is {view.get('iconSize')}, expected {icon_size}")
if int(view.get("textSize", 0)) != text_size:
    problems.append(f"label size is {view.get('textSize')}, expected {text_size}")

if problems:
    print("; ".join(problems))
    sys.exit(1)
print(f"window {window_w}x{window_h}, icons {icon_size}pt at {expected[app_name]} and {expected['Applications']}")
PY
    )"; then
        pass "Finder layout matches: $LAYOUT"
    else
        fail "Finder layout differs from scripts/lib/dmg.sh: $LAYOUT"
    fi
else
    fail "no .DS_Store, the window would open unstyled"
fi

if [ "$FAILURES" -ne 0 ]; then
    echo "error: $LABEL failed $FAILURES check(s)." >&2
    exit 1
fi

# The app as it sits inside the image is what gets dragged to /Applications. dmgbuild copies the
# bundle rather than ditto'ing it, so this is where a lost symlink or a dropped notarization
# ticket would surface.
if [ -d "$APP" ]; then
    "$SCRIPT_DIR/verify_app.sh" "$APP" --require "$REQUIRE"
fi

echo "==> $LABEL passed all disk image checks."
