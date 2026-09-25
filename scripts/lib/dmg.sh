#!/bin/bash
# Shared by scripts/make_dmg.sh and scripts/verify_dmg.sh. Not executable on its own.
#
# The Finder layout of the disk image. These numbers are the contract between the background
# artwork and the .DS_Store the image carries: assets/dmg/background.html mirrors the canvas size
# and icon slots as CSS custom properties, so change both together. docs/releasing.md explains
# each value.

# shellcheck shell=bash

# The background is drawn by Finder at its natural size, anchored top-left, and anything larger
# than the window's content area makes the window scroll. The content area is the window minus
# Finder chrome: a 28pt title bar, plus a 36pt tab bar for anyone who keeps "Show Tab Bar" on.
# So the window is taller than the canvas by DMG_CHROME_H and the canvas bleeds to white.
DMG_CANVAS_W=660
DMG_CANVAS_H=380
DMG_CHROME_H=68
DMG_WINDOW_W=$DMG_CANVAS_W
DMG_WINDOW_H=$((DMG_CANVAS_H + DMG_CHROME_H))

DMG_ICON_SIZE=128
DMG_TEXT_SIZE=13

# Finder positions are the centre of each icon, measured from the top-left of the content area.
DMG_ICON_Y=210
DMG_APP_X=170
DMG_DROP_X=490

DMG_VOLUME_NAME="Meraline"

# Echoes the directory of a Python virtual environment that has dmgbuild (and with it the
# ds_store module the verifier reads .DS_Store through). Bootstrapped into build/.dmg-venv on
# first use, so there is nothing to install by hand and CI and local builds use the same tool.
dmg_python_env() {
    local project_dir="$1"
    local venv="$project_dir/build/.dmg-venv"
    if ! "$venv/bin/python" -c "import dmgbuild, ds_store" >/dev/null 2>&1; then
        echo "==> Installing dmgbuild into build/.dmg-venv" >&2
        rm -rf "$venv"
        python3 -m venv "$venv" >&2
        "$venv/bin/pip" install --quiet --disable-pip-version-check 'dmgbuild~=1.6' >&2
    fi
    printf '%s\n' "$venv"
}
