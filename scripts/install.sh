#!/bin/bash
# Clean Release build, installed into /Applications and launched.
#
# Usage: scripts/install.sh
#
# The build is clean on purpose: Xcode does not recompile the Icon Composer icon incrementally,
# and a stale build once shipped an old logo. With the Developer ID certificate in the keychain
# the app is signed like a release; without it the build is ad-hoc and only runs on this Mac.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
. "$SCRIPT_DIR/lib/signing.sh"
cd "$PROJECT_DIR"

DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/Meraline.app"
TARGET=/Applications/Meraline.app

echo "==> Generating Meraline.xcodeproj"
xcodegen generate --quiet

echo "==> Building Release (clean)"
rm -rf "$DERIVED_DATA/Build"
# shellcheck disable=SC2046
pretty_xcodebuild build/logs/install.log \
    -project Meraline.xcodeproj -scheme Meraline -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" -clonedSourcePackagesDirPath "$PROJECT_DIR/build/SourcePackages" \
    $(adhoc_signing_flags) \
    build

[ -d "$APP" ] || { echo "error: no app at $APP" >&2; exit 1; }

echo "==> Installing to $TARGET"
pkill -x Meraline 2>/dev/null || true
sleep 0.3
rm -rf "$TARGET"
ditto "$APP" "$TARGET"
open "$TARGET"
echo "==> Installed $(plutil -extract CFBundleShortVersionString raw "$TARGET/Contents/Info.plist") ($(plutil -extract CFBundleVersion raw "$TARGET/Contents/Info.plist"))"
