#!/bin/bash
# Shared by the developer scripts. Not executable on its own.
#
# project.yml signs with the Developer ID certificate, which contributors do not have. These
# helpers fall back to an ad-hoc signature when the certificate is missing, which runs fine on
# the Mac that built it. Releases never take this path; scripts/release.sh insists on the
# certificate.

# shellcheck shell=bash

has_developer_id() {
    security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"
}

# Echoes the xcodebuild settings that switch a build to ad-hoc signing when no certificate is
# available, and nothing otherwise. Use as: xcodebuild ... $(adhoc_signing_flags)
adhoc_signing_flags() {
    if ! has_developer_id; then
        printf '%s ' 'CODE_SIGN_IDENTITY=-' 'DEVELOPMENT_TEAM=' 'OTHER_CODE_SIGN_FLAGS='
        echo "==> No Developer ID certificate in the keychain; signing ad-hoc." >&2
    fi
}

# Pipes xcodebuild output through xcbeautify when it is installed, keeping the raw log.
# Usage: pretty_xcodebuild <log-file> <xcodebuild args...>
pretty_xcodebuild() {
    local log="$1"
    shift
    mkdir -p "$(dirname "$log")"
    if command -v xcbeautify >/dev/null 2>&1; then
        xcodebuild "$@" 2>&1 | tee "$log" | xcbeautify --quiet
    else
        xcodebuild "$@" 2>&1 | tee "$log" | awk '/^\*\* |error:|warning: |Test Suite|Test Case|passed|failed/'
    fi
}
