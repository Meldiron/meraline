#!/bin/bash
# Builds Meraline (Debug) and relaunches it from DerivedData. Nothing is installed.
#
# Usage: scripts/dev_run.sh
#
# Output from the running app goes to /tmp/meraline.log. Without a Developer ID certificate the
# build is signed ad-hoc, which is fine for running on this Mac.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
. "$SCRIPT_DIR/lib/signing.sh"
cd "$PROJECT_DIR"

DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/Meraline.app"
LOG=/tmp/meraline.log

echo "==> Generating Meraline.xcodeproj"
xcodegen generate --quiet

echo "==> Building Debug"
# shellcheck disable=SC2046
pretty_xcodebuild build/logs/dev_run.log \
    -project Meraline.xcodeproj -scheme Meraline -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" -clonedSourcePackagesDirPath "$PROJECT_DIR/build/SourcePackages" \
    $(adhoc_signing_flags) \
    build

[ -d "$APP" ] || { echo "error: no app at $APP" >&2; exit 1; }

echo "==> Relaunching from $APP (output in $LOG)"
pkill -x Meraline 2>/dev/null || true
sleep 0.3
open -a "$APP" --stdout "$LOG" --stderr "$LOG"
