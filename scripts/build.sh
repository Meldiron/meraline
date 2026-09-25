#!/bin/bash
# Builds Meraline.app for packaging.
#
# Usage: scripts/build.sh --version <X.Y.Z> [--build <N>] [--adhoc]
#
# Default: `xcodebuild archive` followed by `-exportArchive` with ExportOptions.plist. The export
# is what signs Sparkle's nested helpers (Autoupdate, Updater.app, the XPC services) with the
# Developer ID certificate; a plain archive leaves them with Sparkle's own signature, and the
# notary service returns Invalid. Needs the "Developer ID Application" identity in the keychain.
#
# --adhoc: a plain Release build signed ad-hoc, no certificate required. It exercises the same
# packaging path for CI previews and local checks, but opens only on the Mac that built it.
#
# The build number defaults to the number of commits reachable from HEAD, so a local build and
# the CI build of the same commit agree, and every release is newer than the one before it.
#
# MERALINE_REPOSITORY_URL, MERALINE_FEED_URL, and MERALINE_SPARKLE_PUBLIC_KEY in the environment
# override the repository, Sparkle feed, and public key from project.yml, for forks and for
# rehearsals with a throwaway key.
#
# Output: build/export/Meraline.app, plus build/Meraline.xcarchive for Developer ID builds.
# Full xcodebuild logs go to build/logs/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

VERSION=""
BUILD_NUMBER=""
ADHOC=0
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:-}"; shift 2 ;;
        --build) BUILD_NUMBER="${2:-}"; shift 2 ;;
        --adhoc) ADHOC=1; shift ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; exit 2 ;;
    esac
done
if [ -z "$VERSION" ]; then
    echo "usage: $0 --version <X.Y.Z> [--build <N>] [--adhoc]" >&2
    exit 2
fi
if [ -z "$BUILD_NUMBER" ]; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
fi

DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
PACKAGES="$PROJECT_DIR/build/SourcePackages"
ARCHIVE="$PROJECT_DIR/build/Meraline.xcarchive"
EXPORT_DIR="$PROJECT_DIR/build/export"
LOG_DIR="$PROJECT_DIR/build/logs"
mkdir -p "$LOG_DIR"

# xcodebuild is chatty; xcbeautify keeps the terminal readable and, in GitHub Actions, turns
# errors into annotations. The raw log is always kept so nothing is lost when a build fails.
run_xcodebuild() {
    local name="$1"
    shift
    local log="$LOG_DIR/$name.log"
    if command -v xcbeautify >/dev/null 2>&1; then
        local renderer=()
        [ -n "${GITHUB_ACTIONS:-}" ] && renderer=(--renderer github-actions --is-ci)
        xcodebuild "$@" 2>&1 | tee "$log" | xcbeautify --quiet ${renderer[@]+"${renderer[@]}"}
    else
        xcodebuild "$@" 2>&1 | tee "$log" | awk '/^\*\* |error:|warning: |^Archive |^Exported /'
    fi
}

echo "==> Generating Meraline.xcodeproj"
xcodegen generate --quiet

# A clean build every time: Xcode does not recompile the Icon Composer icon incrementally, and a
# stale build once shipped an old logo. Package checkouts and module caches are kept.
rm -rf "$DERIVED_DATA/Build" "$ARCHIVE" "$EXPORT_DIR"

COMMON=(
    -project "$PROJECT_DIR/Meraline.xcodeproj"
    -scheme Meraline
    -configuration Release
    -destination "generic/platform=macOS"
    -derivedDataPath "$DERIVED_DATA"
    -clonedSourcePackagesDirPath "$PACKAGES"
    MARKETING_VERSION="$VERSION"
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)
# A fork, or a rehearsal with a throwaway Sparkle key, can point the app at its own feed and key
# without editing project.yml. Command-line settings outrank the project's.
[ -z "${MERALINE_REPOSITORY_URL:-}" ] || COMMON+=(MERALINE_REPOSITORY_URL="$MERALINE_REPOSITORY_URL")
[ -z "${MERALINE_FEED_URL:-}" ] || COMMON+=(MERALINE_FEED_URL="$MERALINE_FEED_URL")
[ -z "${MERALINE_SPARKLE_PUBLIC_KEY:-}" ] || COMMON+=(MERALINE_SPARKLE_PUBLIC_KEY="$MERALINE_SPARKLE_PUBLIC_KEY")

if [ "$ADHOC" -eq 1 ]; then
    echo "==> Building Meraline $VERSION ($BUILD_NUMBER), ad-hoc signed"
    # CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps Xcode from adding the get-task-allow debugging
    # entitlement that non-archive builds normally get, so the preview matches a release.
    run_xcodebuild build "${COMMON[@]}" \
        CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" OTHER_CODE_SIGN_FLAGS="" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        build
    mkdir -p "$EXPORT_DIR"
    ditto "$DERIVED_DATA/Build/Products/Release/Meraline.app" "$EXPORT_DIR/Meraline.app"
else
    echo "==> Archiving Meraline $VERSION ($BUILD_NUMBER) with Developer ID"
    run_xcodebuild archive "${COMMON[@]}" -archivePath "$ARCHIVE" archive

    echo "==> Exporting the archive"
    run_xcodebuild export \
        -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
        -exportPath "$EXPORT_DIR"
fi

APP="$EXPORT_DIR/Meraline.app"
if [ ! -d "$APP" ]; then
    echo "error: the build did not produce $APP" >&2
    exit 1
fi

BUILT_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILT_NUMBER="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ] || [ "$BUILT_NUMBER" != "$BUILD_NUMBER" ]; then
    echo "error: built $BUILT_VERSION ($BUILT_NUMBER), expected $VERSION ($BUILD_NUMBER)" >&2
    exit 1
fi
echo "==> Built $APP: version $BUILT_VERSION, build $BUILT_NUMBER"
