#!/bin/bash
# Runs the test suite.
#
# Usage: scripts/test.sh [SuiteName] [--e2e] [--verbose]
#
#   SuiteName   run one Swift Testing struct, e.g. scripts/test.sh HistoryTests
#   --e2e       also run the installed claude, codex, and opencode commands for real
#   --verbose   raw xcodebuild output instead of the xcbeautify summary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/signing.sh
. "$SCRIPT_DIR/lib/signing.sh"
cd "$PROJECT_DIR"

SUITE=""
E2E=0
VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --e2e) E2E=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option $1" >&2; exit 2 ;;
        *) SUITE="$1"; shift ;;
    esac
done

echo "==> Generating Meraline.xcodeproj"
xcodegen generate --quiet

ARGS=(
    -project Meraline.xcodeproj -scheme Meraline
    -destination 'platform=macOS'
    -derivedDataPath "$PROJECT_DIR/build/DerivedData"
    -clonedSourcePackagesDirPath "$PROJECT_DIR/build/SourcePackages"
)
[ -z "$SUITE" ] || ARGS+=("-only-testing:MeralineTests/$SUITE")
[ "$E2E" -eq 0 ] || export TEST_RUNNER_MERALINE_CLI_E2E=1

echo "==> Testing${SUITE:+ $SUITE}${E2E:+}"
if [ "$VERBOSE" -eq 1 ]; then
    # shellcheck disable=SC2046
    xcodebuild "${ARGS[@]}" $(adhoc_signing_flags) test
else
    # shellcheck disable=SC2046
    pretty_xcodebuild build/logs/test.log "${ARGS[@]}" $(adhoc_signing_flags) test
fi
