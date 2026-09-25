#!/bin/bash
# Fails unless a Meraline artifact is signed the way a release has to ship.
#
# Usage: scripts/verify_app.sh <Meraline.app|Meraline.dmg> [--require <level>]
#
# Levels:
#   any           (default) a structurally valid signature, the hardened runtime on the app and on
#                 every nested binary, one consistent signer throughout, and universal (arm64 and
#                 x86_64) code. Passes for ad-hoc builds.
#   developer-id  the above, plus a Developer ID Application certificate, a secure timestamp, a
#                 Team ID, and no get-task-allow entitlement (the notary service rejects it).
#   notarized     the above, plus a stapled notarization ticket and a Gatekeeper assessment that
#                 accepts the artifact as Notarized Developer ID, repeated on a quarantined copy so
#                 the verdict is the one a download actually gets.
#
# Build settings are not enough to know any of this. The finished artifact is what Gatekeeper
# reads, so that is what gets inspected here, nested Sparkle helpers included: Xcode signs them
# only during the export step, and a single ad-hoc helper is enough to fail notarization.

set -euo pipefail

TARGET=""
REQUIRE="any"
while [ $# -gt 0 ]; do
    case "$1" in
        --require) REQUIRE="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) TARGET="$1"; shift ;;
    esac
done
case "$REQUIRE" in
    any|developer-id|notarized) ;;
    *) echo "error: --require must be any, developer-id, or notarized (got \"$REQUIRE\")" >&2; exit 2 ;;
esac
if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
    echo "usage: $0 <Meraline.app|Meraline.dmg> [--require any|developer-id|notarized]" >&2
    exit 2
fi
TARGET="${TARGET%/}"
LABEL="$(basename "$TARGET")"
IS_APP=0
[ -d "$TARGET" ] && IS_APP=1

FAILURES=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1" >&2; FAILURES=$((FAILURES + 1)); }

# codesign -dvv reports on stderr; captured once per item and queried repeatedly.
report() { codesign -dvv "$1" 2>&1 || true; }
has_flag() { grep -qE "^CodeDirectory .*flags=.*$2" <<<"$1"; }
team_of() { sed -n 's/^TeamIdentifier=\(.*\)$/\1/p' <<<"$1" | head -1 | sed 's/^not set$//'; }
is_macho() { file -b "$1" | grep -q "Mach-O"; }

# Every item inside the bundle that carries a signature of its own: nested bundles and loose
# Mach-O executables. Symlinks are skipped (Sparkle.framework/Versions/Current and friends point
# at items that are listed in their own right).
nested_code_items() {
    local app="$1"
    find "$app" -mindepth 1 \( -name "*.framework" -o -name "*.app" -o -name "*.xpc" -o -name "*.bundle" \) -type d -print
    find "$app" -type f -print0 | while IFS= read -r -d '' f; do
        is_macho "$f" && printf '%s\n' "$f"
    done
}

# True when a bundle contains executable code. Resource-only bundles (SwiftPM emits one for
# KeyboardShortcuts' assets) are signed but have nothing to harden.
contains_code() {
    local path="$1"
    [ -f "$path" ] && { is_macho "$path"; return; }
    [ -n "$(find "$path" -type f -print0 | while IFS= read -r -d '' f; do is_macho "$f" && echo yes && break; done)" ]
}

echo "==> Verifying $LABEL (--require $REQUIRE)"
REPORT="$(report "$TARGET")"
if ! grep -q "^CodeDirectory" <<<"$REPORT"; then
    fail "$LABEL is not signed at all"
    echo "error: $LABEL failed verification." >&2
    exit 1
fi

IS_ADHOC=0
has_flag "$REPORT" adhoc && IS_ADHOC=1
TEAM_ID="$(team_of "$REPORT")"

if codesign --verify --deep --strict --verbose=2 "$TARGET" >/dev/null 2>&1; then
    pass "signature is structurally valid (--deep --strict)"
else
    fail "codesign --verify --deep --strict failed:"
    codesign --verify --deep --strict --verbose=2 "$TARGET" 2>&1 | sed 's/^/      /' >&2 || true
fi

if [ "$IS_APP" -eq 1 ]; then
    if has_flag "$REPORT" runtime; then
        pass "hardened runtime enabled"
    else
        fail "hardened runtime is off; notarization will be refused"
    fi

    # Each nested binary is checked in its own right. One ad-hoc helper fails notarization, and
    # mixed teams break Sparkle's check that its updater belongs to the app that launched it.
    NESTED_TOTAL=0
    NESTED_BAD=0
    THIN=0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        NESTED_TOTAL=$((NESTED_TOTAL + 1))
        REL="${item#"$TARGET"/}"
        # A bundle with no executable code (SwiftPM's resource bundles) has nothing the notary
        # service or the hardened runtime applies to; it is sealed by the app's own signature.
        contains_code "$item" || continue
        ITEM_REPORT="$(report "$item")"
        if ! has_flag "$ITEM_REPORT" runtime; then
            fail "$REL is not signed with the hardened runtime"
            NESTED_BAD=$((NESTED_BAD + 1))
        fi
        if [ "$IS_ADHOC" -eq 0 ] && has_flag "$ITEM_REPORT" adhoc; then
            fail "$REL is still ad-hoc signed while the app is not; notarization would reject it"
            NESTED_BAD=$((NESTED_BAD + 1))
        fi
        if [ -n "$TEAM_ID" ] && [ "$(team_of "$ITEM_REPORT")" != "$TEAM_ID" ]; then
            fail "$REL is signed by team \"$(team_of "$ITEM_REPORT")\", expected \"$TEAM_ID\""
            NESTED_BAD=$((NESTED_BAD + 1))
        fi
        if [ -f "$item" ]; then
            ARCHS="$(lipo -archs "$item" 2>/dev/null || true)"
            for arch in arm64 x86_64; do
                case " $ARCHS " in
                    *" $arch "*) ;;
                    *) fail "$REL is missing the $arch slice (has: ${ARCHS:-nothing})"; THIN=$((THIN + 1)) ;;
                esac
            done
        fi
    done < <(nested_code_items "$TARGET")

    if [ "$NESTED_TOTAL" -eq 0 ]; then
        fail "found no nested code under $LABEL; wrong path?"
    else
        [ "$NESTED_BAD" -eq 0 ] && pass "all nested code hardened and signed by the same team"
        [ "$THIN" -eq 0 ] && pass "every binary is universal (arm64 and x86_64)"
    fi
fi

if [ "$REQUIRE" != "any" ]; then
    if [ "$IS_ADHOC" -eq 1 ]; then
        fail "$LABEL is ad-hoc signed; --require $REQUIRE needs a Developer ID Application certificate"
    else
        AUTHORITY="$(sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' <<<"$REPORT" | head -1)"
        if [ -n "$AUTHORITY" ]; then
            pass "signed by $AUTHORITY"
        else
            fail "not signed by a Developer ID Application certificate (found: $(sed -n 's/^Authority=\(.*\)$/\1/p' <<<"$REPORT" | head -1))"
        fi
        # Without a secure timestamp the signature stops verifying when the certificate expires,
        # and the notary service refuses the submission outright.
        if grep -q "^Timestamp=" <<<"$REPORT"; then
            pass "secure timestamp present"
        else
            fail "no secure timestamp; sign with --timestamp"
        fi
        if [ -n "$TEAM_ID" ]; then
            pass "Team ID $TEAM_ID"
        else
            fail "no Team ID in the signature"
        fi
        if [ "$IS_APP" -eq 1 ]; then
            # Xcode injects this debugging entitlement into non-archive builds; the notary
            # service rejects anything that carries it.
            if codesign -d --entitlements - --xml "$TARGET" 2>/dev/null | grep -q "com.apple.security.get-task-allow"; then
                fail "entitlements include com.apple.security.get-task-allow (build came from xcodebuild build, not an export)"
            else
                pass "no debugging entitlement"
            fi
        fi
    fi
fi

if [ "$REQUIRE" = "notarized" ]; then
    if xcrun stapler validate "$TARGET" >/dev/null 2>&1; then
        pass "notarization ticket is stapled (verifies offline)"
    else
        fail "no stapled notarization ticket:"
        xcrun stapler validate "$TARGET" 2>&1 | sed 's/^/      /' >&2 || true
    fi

    # Gatekeeper's own verdict. A disk image is assessed as something the user opens, and the
    # primary-signature context makes spctl judge the image's signature rather than look for a
    # document handler.
    assess() {
        if [ "$IS_APP" -eq 1 ]; then
            spctl -a -vv -t exec "$1" 2>&1 || true
        else
            spctl -a -vv -t open --context context:primary-signature "$1" 2>&1 || true
        fi
    }
    VERDICT="$(assess "$TARGET")"
    if grep -q "accepted" <<<"$VERDICT" && grep -q "source=Notarized Developer ID" <<<"$VERDICT"; then
        pass "Gatekeeper accepts it as Notarized Developer ID"
    else
        fail "Gatekeeper did not accept it:"
        sed 's/^/      /' <<<"$VERDICT" >&2
    fi

    # The assessment above ran on a file with no quarantine attribute. A download arrives with
    # one, so repeat it on a quarantined copy to get the verdict a user would.
    QUARANTINE_DIR="$(mktemp -d)"
    trap 'rm -rf "$QUARANTINE_DIR"' EXIT
    ditto "$TARGET" "$QUARANTINE_DIR/$LABEL"
    xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$QUARANTINE_DIR/$LABEL"
    QUARANTINED="$(assess "$QUARANTINE_DIR/$LABEL")"
    if grep -q "accepted" <<<"$QUARANTINED"; then
        pass "still accepted once quarantined like a download"
    else
        fail "rejected once quarantined; users would see Gatekeeper's warning:"
        sed 's/^/      /' <<<"$QUARANTINED" >&2
    fi
fi

if [ "$FAILURES" -ne 0 ]; then
    echo "error: $LABEL failed verification ($FAILURES problem(s))." >&2
    exit 1
fi
if [ "$IS_ADHOC" -eq 1 ]; then
    echo "==> $LABEL is a valid ad-hoc build. It opens only on the Mac that built it."
else
    echo "==> $LABEL passed all --require $REQUIRE checks."
fi
