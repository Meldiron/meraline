#!/bin/bash
# Prints the release notes for a version as Markdown.
#
# Usage: scripts/release_notes.sh <X.Y.Z>
#
# If CHANGELOG.md has a "## vX.Y.Z" heading, that section is used, so a hand-written entry wins
# whenever there is one. Otherwise the notes list the commits since the previous tag. The result
# goes into the GitHub release and, as HTML, into the Sparkle update window.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "usage: $0 <X.Y.Z>" >&2
    exit 2
fi
REPO="${MERALINE_REPO:-Meldiron/meraline}"

CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
if [ -f "$CHANGELOG" ]; then
    ENTRY="$(awk -v version="$VERSION" '
        /^## / {
            heading = $2
            sub(/^\[/, "", heading); sub(/\]$/, "", heading); sub(/^v/, "", heading)
            found = (heading == version)
            next
        }
        found && !/^---$/ { print }
    ' "$CHANGELOG" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
    if [ -n "$ENTRY" ]; then
        printf '%s\n' "$ENTRY"
        exit 0
    fi
fi

# No changelog entry: list what went in since the previous tag. When this version's own tag
# exists, the search for the previous one starts just below it; otherwise a tag on HEAD itself
# counts as the previous release.
TAG="v$VERSION"
if git -C "$PROJECT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    HEAD_REF="$TAG"
    SEARCH_FROM="$TAG^"
else
    HEAD_REF="HEAD"
    SEARCH_FROM="HEAD"
fi
PREVIOUS="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 --match 'v*' "$SEARCH_FROM" 2>/dev/null || true)"
if [ -n "$PREVIOUS" ]; then
    RANGE="$PREVIOUS..$HEAD_REF"
else
    RANGE="$HEAD_REF"
fi

COMMITS="$(git -C "$PROJECT_DIR" log --no-merges --format='- %s' "$RANGE" 2>/dev/null || true)"
if [ -z "$COMMITS" ]; then
    echo "Meraline $VERSION."
    exit 0
fi

printf '%s\n' "$COMMITS"
if [ -n "$PREVIOUS" ]; then
    printf '\n**Full changelog:** https://github.com/%s/compare/%s...%s\n' "$REPO" "$PREVIOUS" "$TAG"
fi
