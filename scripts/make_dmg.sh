#!/bin/bash
# Builds the styled Meraline disk image: a rendered background, the app on the left, a link to
# /Applications on the right, an arrow between them, and the app icon as the volume icon.
#
# Usage: scripts/make_dmg.sh <path/to/Meraline.app> <output.dmg> [volume-name]
#
# The image is produced by dmgbuild, which writes the Finder .DS_Store directly instead of driving
# Finder over AppleScript. That needs no GUI session, so the same command works on a CI runner, and
# only the two visible items get a saved position, which keeps hidden files from widening the
# window into a scroll bar. See docs/releasing.md for the layout contract and design notes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/dmg.sh
. "$SCRIPT_DIR/lib/dmg.sh"

APP_PATH="${1:-}"
OUTPUT_DMG="${2:-}"
VOLUME_NAME="${3:-$DMG_VOLUME_NAME}"

if [ -z "$APP_PATH" ] || [ -z "$OUTPUT_DMG" ]; then
    echo "usage: $0 <path/to/Meraline.app> <output.dmg> [volume-name]" >&2
    exit 2
fi
APP_PATH="${APP_PATH%/}"
if [ ! -d "$APP_PATH" ] || [ ! -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "error: $APP_PATH is not an app bundle" >&2
    exit 1
fi

VENV="$(dmg_python_env "$PROJECT_DIR")"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Rendering the background from assets/dmg/background.html"
BACKGROUND="$PROJECT_DIR/assets/dmg/background.html"
swift "$SCRIPT_DIR/render_html_png.swift" "$BACKGROUND" "$WORK_DIR/background.png" "$DMG_CANVAS_W" "$DMG_CANVAS_H" 1 >/dev/null
swift "$SCRIPT_DIR/render_html_png.swift" "$BACKGROUND" "$WORK_DIR/background@2x.png" "$DMG_CANVAS_W" "$DMG_CANVAS_H" 2 >/dev/null

# One TIFF with both renditions lets Finder pick the 2x image on Retina displays. A single 1x
# PNG looks soft on every modern Mac, and a lone 2x PNG is drawn at twice the intended size.
sips -s format tiff "$WORK_DIR/background.png" --out "$WORK_DIR/background-1x.tiff" >/dev/null
sips -s format tiff "$WORK_DIR/background@2x.png" --out "$WORK_DIR/background-2x.tiff" >/dev/null
tiffutil -cathidpicheck "$WORK_DIR/background-1x.tiff" "$WORK_DIR/background-2x.tiff" \
    -out "$WORK_DIR/background.tiff" >/dev/null

# The mounted volume shows the app's own icon in the sidebar and on the desktop. Xcode writes
# AppIcon.icns into the bundle alongside the asset catalog, so nothing has to be kept in sync.
VOLUME_ICON=""
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$WORK_DIR/VolumeIcon.icns"
    VOLUME_ICON="$WORK_DIR/VolumeIcon.icns"
else
    echo "warning: no AppIcon.icns in the bundle; the volume gets the generic disk icon" >&2
fi

APP_NAME="$(basename "$APP_PATH")"

# hide_extensions is deliberately left off. It stores Finder's hidden-extension bit in a
# com.apple.FinderInfo attribute on the bundle inside the image, and codesign --strict counts
# that attribute as detritus, so the copy a user drags out of the image would fail to verify.
# Finder hides .app extensions by default anyway.
cat > "$WORK_DIR/settings.py" <<PYTHON
format = "UDZO"
compression_level = 9
files = [r"""$APP_PATH"""]
symlinks = {"Applications": "/Applications"}
icon = r"""$VOLUME_ICON""" or None
background = r"""$WORK_DIR/background.tiff"""

default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
label_pos = "bottom"

# Bottom-up Cocoa coordinates: a huge y makes Finder clamp the window to the top of the screen,
# the one placement that looks the same on every display size.
window_rect = ((200, 100000), ($DMG_WINDOW_W, $DMG_WINDOW_H))
icon_size = $DMG_ICON_SIZE
text_size = $DMG_TEXT_SIZE
icon_locations = {
    "$APP_NAME": ($DMG_APP_X, $DMG_ICON_Y),
    "Applications": ($DMG_DROP_X, $DMG_ICON_Y),
}
PYTHON

echo "==> Building $(basename "$OUTPUT_DMG")"
mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"
"$VENV/bin/dmgbuild" -s "$WORK_DIR/settings.py" "$VOLUME_NAME" "$OUTPUT_DMG"

SIZE="$(du -h "$OUTPUT_DMG" | cut -f1 | tr -d ' ')"
echo "==> Created $OUTPUT_DMG ($SIZE)"
