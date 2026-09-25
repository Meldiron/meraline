#!/bin/bash
# Submits an artifact to Apple's notary service, waits for the verdict, and staples the ticket.
#
# Usage: scripts/notarize.sh <Meraline.app|Meraline.dmg>
#
# Stapling is what matters for a download: it writes the ticket into the artifact so Gatekeeper
# can accept it without asking Apple at launch, including on a Mac that is offline.
#
# An app bundle cannot be submitted as-is, so it is zipped to a scratch directory for the upload
# and the ticket is stapled onto the original bundle. A disk image is submitted directly.
#
# Credentials, first complete group wins:
#   NOTARY_PROFILE                              a profile saved with `xcrun notarytool store-credentials`
#   NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER_ID App Store Connect API key. NOTARY_KEY is either a
#                                               path to the .p8 file or the key text itself, so a CI
#                                               secret can be passed straight through.
#
# NOTARY_TIMEOUT (default 30m) caps how long to wait for a verdict.

set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
    echo "usage: $0 <Meraline.app|Meraline.dmg>" >&2
    exit 2
fi
TARGET="${TARGET%/}"
LABEL="$(basename "$TARGET")"

WORK_DIR="$(mktemp -d)"
# The scratch directory may hold a private key written out of the environment, so it goes away
# on every exit path.
trap 'rm -rf "$WORK_DIR"' EXIT

CREDENTIALS=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
    CREDENTIALS=(--keychain-profile "$NOTARY_PROFILE")
    echo "==> Notarizing $LABEL with keychain profile \"$NOTARY_PROFILE\""
elif [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    KEY_PATH="$NOTARY_KEY"
    if [ ! -f "$KEY_PATH" ]; then
        KEY_PATH="$WORK_DIR/AuthKey.p8"
        (umask 077; printf '%s\n' "$NOTARY_KEY" > "$KEY_PATH")
        if ! grep -q "BEGIN PRIVATE KEY" "$KEY_PATH"; then
            echo "error: NOTARY_KEY is neither a readable file nor a PEM private key." >&2
            exit 1
        fi
    fi
    CREDENTIALS=(--key "$KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    echo "==> Notarizing $LABEL with App Store Connect key $NOTARY_KEY_ID"
else
    cat >&2 <<'MSG'
error: no notarization credentials configured. Set one of:

    NOTARY_PROFILE                                  (saved with `xcrun notarytool store-credentials`)
    NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER_ID     (App Store Connect API key)

  The key ID is the XXXXXXXXXX in AuthKey_XXXXXXXXXX.p8. The issuer ID is the UUID shown above
  the key list in App Store Connect under Users and Access > Integrations > Team Keys.
MSG
    exit 1
fi

if [ -d "$TARGET" ]; then
    SUBMISSION="$WORK_DIR/${LABEL%.app}.zip"
    # The same ditto flags as the release archive, so the notary service sees the layout users get.
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$SUBMISSION"
else
    SUBMISSION="$TARGET"
fi

echo "==> Submitting $(basename "$SUBMISSION") (this usually takes a few minutes)"
RESULT="$WORK_DIR/submit.json"
STATUS=0
xcrun notarytool submit "$SUBMISSION" "${CREDENTIALS[@]}" \
    --wait --timeout "${NOTARY_TIMEOUT:-30m}" --output-format json \
    > "$RESULT" 2> "$WORK_DIR/submit.err" || STATUS=$?

SUBMISSION_ID="$(jq -r '.id // empty' "$RESULT" 2>/dev/null || true)"
VERDICT="$(jq -r '.status // empty' "$RESULT" 2>/dev/null || true)"

# notarytool exits 0 for Invalid as well as Accepted, so the status field is what decides.
if [ "$VERDICT" != "Accepted" ]; then
    echo "error: notarization of $LABEL did not succeed (status: ${VERDICT:-unknown}, exit $STATUS)." >&2
    [ -s "$WORK_DIR/submit.err" ] && sed 's/^/      /' "$WORK_DIR/submit.err" >&2
    if [ -n "$SUBMISSION_ID" ]; then
        # Apple's log is the only place that says why; without it the failure is unactionable.
        echo "--- notarytool log for $SUBMISSION_ID ---" >&2
        xcrun notarytool log "$SUBMISSION_ID" "${CREDENTIALS[@]}" 2>&1 | sed 's/^/      /' >&2 || true
    fi
    exit 1
fi
echo "==> Accepted (submission $SUBMISSION_ID)"

echo "==> Stapling the ticket to $LABEL"
xcrun stapler staple -q "$TARGET"
xcrun stapler validate -q "$TARGET"
echo "==> $LABEL is notarized and stapled."
