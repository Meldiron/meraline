#!/bin/bash
# Builds, signs, notarizes, and packages a Meraline release. The Release workflow runs exactly
# this script, so a release can be reproduced or rehearsed on a Mac with the same inputs.
#
# Usage: scripts/release.sh <X.Y.Z> [--build <N>] [--adhoc | --no-notarize]
#
# Output in build/release:
#   Meraline-<version>.dmg         styled disk image, signed and notarized in its own right
#   Meraline-<version>.zip         the archive Sparkle installs
#   appcast.xml                    the Sparkle feed entry, EdDSA-signed, with release notes embedded
#   Meraline-<version>-dSYMs.zip   debug symbols for crash reports
#   SHA256SUMS.txt
# and the release notes as Markdown in build/notes/.
#
# Modes:
#   default        Developer ID signing, notarization, and stapling; every artifact is checked the
#                  way a user receives it. Needs the "Developer ID Application" identity in the
#                  keychain, notary credentials (see scripts/notarize.sh), and the Sparkle private
#                  key: SPARKLE_PRIVATE_KEY in the environment, or Sparkle's entry in the keychain.
#   --no-notarize  Developer ID signing without notarization, to inspect a signed build locally.
#   --adhoc        Ad-hoc signing, no notarization, no appcast. Runs the whole pipeline with no
#                  credentials at all; the artifacts open only on the Mac that built them.
#
# The build number defaults to the commit count of HEAD (see scripts/build.sh). MERALINE_REPO
# overrides the GitHub repository the download URLs point at (default Meldiron/meraline).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

VERSION=""
BUILD_NUMBER=""
MODE="release"
while [ $# -gt 0 ]; do
    case "$1" in
        --build) BUILD_NUMBER="${2:-}"; shift 2 ;;
        --adhoc) MODE="adhoc"; shift ;;
        --no-notarize) MODE="signed"; shift ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) [ -z "$VERSION" ] || { echo "error: unexpected argument $1" >&2; exit 2; }; VERSION="$1"; shift ;;
    esac
done
if [ -z "$VERSION" ]; then
    echo "usage: $0 <X.Y.Z> [--build <N>] [--adhoc | --no-notarize]" >&2
    exit 2
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    echo "error: \"$VERSION\" is not a version like 1.2.0 or 1.2.0-beta.1" >&2
    exit 2
fi
[ -n "$BUILD_NUMBER" ] || BUILD_NUMBER="$(git rev-list --count HEAD)"

REPO="${MERALINE_REPO:-Meldiron/meraline}"
TAG="v$VERSION"
RELEASE_DIR="$PROJECT_DIR/build/release"
NOTES_DIR="$PROJECT_DIR/build/notes"
APPCAST_DIR="$PROJECT_DIR/build/appcast"
VERIFY_DIR="$PROJECT_DIR/build/.verify"
APP="$PROJECT_DIR/build/export/Meraline.app"
ZIP="Meraline-$VERSION.zip"
DMG="Meraline-$VERSION.dmg"
DSYMS="Meraline-$VERSION-dSYMs.zip"
NOTES="Meraline-$VERSION.md"

# Collapsible sections in the GitHub Actions log, plain headings elsewhere.
group() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$1"; else printf '\n━━ %s\n' "$1"; fi
}
endgroup() { [ -z "${GITHUB_ACTIONS:-}" ] || echo "::endgroup::"; }
die() { echo "error: $1" >&2; exit 1; }

group "Checking prerequisites"
for tool in xcodegen jq swift python3 hdiutil tiffutil; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
case "$MODE" in
    adhoc)
        echo "Mode: ad-hoc. No certificate, no notarization, no appcast. Not distributable."
        ;;
    signed|release)
        FOUND="$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Developer ID Application" || true)"
        [ "$FOUND" -ge 1 ] || die "no \"Developer ID Application\" identity in the keychain. Import the certificate, or pass --adhoc."
        echo "Signing identity: $(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
        if [ "$MODE" = "release" ]; then
            if [ -n "${NOTARY_PROFILE:-}" ]; then
                echo "Notary credentials: keychain profile $NOTARY_PROFILE"
            elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
                echo "Notary credentials: App Store Connect key $NOTARY_KEY_ID"
            else
                die "no notary credentials. Set NOTARY_PROFILE, or NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER_ID (see scripts/notarize.sh), or pass --no-notarize."
            fi
            if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
                echo "Sparkle key: SPARKLE_PRIVATE_KEY"
            elif security find-generic-password -s "https://sparkle-project.org" -a ed25519 >/dev/null 2>&1; then
                echo "Sparkle key: keychain"
            else
                die "no Sparkle EdDSA private key. Set SPARKLE_PRIVATE_KEY, or run Sparkle's generate_keys on this Mac."
            fi
        else
            echo "Mode: signed, not notarized. Not distributable."
        fi
        ;;
esac
# A version with a pre-release suffix (1.2.0-beta.1) goes out on Sparkle's beta channel: its appcast
# item carries <sparkle:channel>beta</sparkle:channel>, which only clients that opted into the beta
# channel accept. The workflow copies every release's appcast onto the rolling `beta` release, so
# the beta feed always advertises the newest build, stable or beta.
CHANNEL="stable"
case "$VERSION" in *-*) CHANNEL="beta" ;; esac
echo "Version $VERSION, build $BUILD_NUMBER, $CHANNEL channel, downloads from https://github.com/$REPO/releases/download/$TAG/"
endgroup

REQUIRE="developer-id"
[ "$MODE" = "adhoc" ] && REQUIRE="any"

group "Building Meraline.app"
BUILD_FLAGS=(--version "$VERSION" --build "$BUILD_NUMBER")
[ "$MODE" = "adhoc" ] && BUILD_FLAGS+=(--adhoc)
"$SCRIPT_DIR/build.sh" "${BUILD_FLAGS[@]}"
endgroup

group "Verifying the app"
"$SCRIPT_DIR/verify_app.sh" "$APP" --require "$REQUIRE"
endgroup

# Notarize and staple before anything is cut from the bundle, so the ticket travels inside the
# zip, inside the disk image, and under the Sparkle signature.
if [ "$MODE" = "release" ]; then
    group "Notarizing the app"
    "$SCRIPT_DIR/notarize.sh" "$APP"
    REQUIRE="notarized"
    "$SCRIPT_DIR/verify_app.sh" "$APP" --require "$REQUIRE"
    endgroup
fi

rm -rf "$RELEASE_DIR" "$NOTES_DIR" "$APPCAST_DIR" "$VERIFY_DIR"
mkdir -p "$RELEASE_DIR" "$NOTES_DIR" "$APPCAST_DIR" "$VERIFY_DIR"

group "Packaging $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/$ZIP"
# Check the app as it comes out of the archive, not the bundle it was cut from: this is what
# proves the notarization ticket survived the trip through ditto.
ditto -x -k "$RELEASE_DIR/$ZIP" "$VERIFY_DIR"
"$SCRIPT_DIR/verify_app.sh" "$VERIFY_DIR/Meraline.app" --require "$REQUIRE"
rm -rf "$VERIFY_DIR"
endgroup

group "Writing release notes"
"$SCRIPT_DIR/release_notes.sh" "$VERSION" > "$NOTES_DIR/$NOTES"
sed 's/^/    /' "$NOTES_DIR/$NOTES"
endgroup

if [ "$MODE" != "adhoc" ]; then
    group "Generating appcast.xml"
    GENERATE_APPCAST="$(find "$PROJECT_DIR/build/SourcePackages/artifacts" -type f -name generate_appcast -perm +111 2>/dev/null | head -1)"
    [ -n "$GENERATE_APPCAST" ] || die "Sparkle's generate_appcast was not found under build/SourcePackages"

    # generate_appcast works on a directory of archives, so it gets one holding only this
    # release's zip and its notes. A .md next to the archive becomes the item's release notes,
    # which the Sparkle update window shows to users.
    cp "$RELEASE_DIR/$ZIP" "$APPCAST_DIR/$ZIP"
    cp "$NOTES_DIR/$NOTES" "$APPCAST_DIR/$NOTES"
    rm -rf ~/Library/Caches/Sparkle_generate_appcast

    APPCAST_ARGS=()
    [ "$CHANNEL" = "stable" ] || APPCAST_ARGS+=(--channel "$CHANNEL")
    APPCAST_ARGS+=(
        --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
        --link "https://github.com/$REPO"
        --full-release-notes-url "https://github.com/$REPO/releases/tag/$TAG"
        --embed-release-notes
        -o "$APPCAST_DIR/appcast.xml"
        "$APPCAST_DIR"
    )
    if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
        printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - "${APPCAST_ARGS[@]}"
    else
        "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}"
    fi

    APPCAST="$APPCAST_DIR/appcast.xml"
    [ -f "$APPCAST" ] || die "generate_appcast produced no appcast.xml"
    [ "$(grep -c '<item>' "$APPCAST")" -eq 1 ] || die "appcast.xml should hold exactly one item"
    grep -q 'sparkle:edSignature="' "$APPCAST" || die "appcast.xml has no EdDSA signature"
    grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST" || die "appcast.xml does not announce version $VERSION"
    grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$APPCAST" || die "appcast.xml does not carry build $BUILD_NUMBER"
    grep -q "url=\"https://github.com/$REPO/releases/download/$TAG/$ZIP\"" "$APPCAST" || die "appcast.xml points somewhere other than the $TAG release"
    grep -q '<description' "$APPCAST" || die "appcast.xml has no embedded release notes"
    if [ "$CHANNEL" = "beta" ]; then
        grep -q "<sparkle:channel>beta</sparkle:channel>" "$APPCAST" || die "appcast.xml is not tagged for the beta channel"
    else
        ! grep -q "<sparkle:channel>" "$APPCAST" || die "a stable appcast.xml must not carry a channel"
    fi
    cp "$APPCAST" "$RELEASE_DIR/appcast.xml"
    echo "appcast.xml: version $VERSION ($BUILD_NUMBER), $(stat -f %z "$RELEASE_DIR/$ZIP") bytes, signed"
    endgroup
fi

group "Building $DMG"
"$SCRIPT_DIR/make_dmg.sh" "$APP" "$RELEASE_DIR/$DMG"
if [ "$MODE" != "adhoc" ]; then
    # Gatekeeper assesses the disk image itself before the user reaches the app inside, so it
    # gets its own signature, from the very certificate the app was exported with.
    IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -1)"
    [ -n "$IDENTITY" ] || die "could not read the signing identity off $APP"
    echo "==> Signing $DMG as $IDENTITY"
    codesign --force --sign "$IDENTITY" --timestamp "$RELEASE_DIR/$DMG"
fi
if [ "$MODE" = "release" ]; then
    "$SCRIPT_DIR/notarize.sh" "$RELEASE_DIR/$DMG"
fi
"$SCRIPT_DIR/verify_dmg.sh" "$RELEASE_DIR/$DMG" --require "$REQUIRE"
endgroup

if [ -d "$PROJECT_DIR/build/Meraline.xcarchive/dSYMs" ]; then
    group "Packaging $DSYMS"
    ditto -c -k "$PROJECT_DIR/build/Meraline.xcarchive/dSYMs" "$RELEASE_DIR/$DSYMS"
    echo "$(ls "$PROJECT_DIR/build/Meraline.xcarchive/dSYMs" | wc -l | tr -d ' ') dSYM bundles"
    endgroup
fi

group "Checksums"
(
    cd "$RELEASE_DIR"
    FILES=("$DMG" "$ZIP")
    [ -f "$DSYMS" ] && FILES+=("$DSYMS")
    shasum -a 256 "${FILES[@]}" > SHA256SUMS.txt
    cat SHA256SUMS.txt
)
endgroup

printf '\n==> Meraline %s (build %s) is ready in build/release:\n' "$VERSION" "$BUILD_NUMBER"
(cd "$RELEASE_DIR" && ls -1 | while IFS= read -r f; do printf '    %-32s %s\n' "$f" "$(du -h "$f" | cut -f1 | tr -d ' ')"; done)
case "$MODE" in
    adhoc)  echo "    ad-hoc signed: for testing the pipeline only, do not publish." ;;
    signed) echo "    signed but not notarized: do not publish." ;;
    release) echo "    signed, notarized, and stapled: app and disk image." ;;
esac

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "version=$VERSION"
        echo "build=$BUILD_NUMBER"
        echo "channel=$CHANNEL"
        echo "dmg=$RELEASE_DIR/$DMG"
        echo "zip=$RELEASE_DIR/$ZIP"
    } >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Meraline $VERSION (build $BUILD_NUMBER)"
        echo
        echo "| File | Size | SHA-256 |"
        echo "| --- | --- | --- |"
        while read -r sum name; do
            echo "| \`$name\` | $(du -h "$RELEASE_DIR/$name" | cut -f1 | tr -d ' ') | \`$sum\` |"
        done < "$RELEASE_DIR/SHA256SUMS.txt"
    } >> "$GITHUB_STEP_SUMMARY"
fi
