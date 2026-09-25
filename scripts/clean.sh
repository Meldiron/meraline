#!/bin/bash
# Removes build output: build/ (DerivedData, packages, release artifacts, the dmgbuild venv) and
# any Meraline DerivedData Xcode itself created.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$PROJECT_DIR/build"
rm -rf "$HOME"/Library/Developer/Xcode/DerivedData/Meraline-*
echo "==> Clean."
