#!/usr/bin/env bash
set -euo pipefail

# Loom — Automated Release Pipeline Verification Probe
# Asserts structural invariants across release scripts without requiring Apple notarization credentials.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PASS_COUNT=0
FAIL_COUNT=0

check() {
    local desc="$1"
    local condition="$2"
    echo -n "Checking ${desc}... "
    if eval "${condition}"; then
        echo "[PASS]"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[FAIL]"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "=========================================================="
echo "Loom Release Pipeline Structural Verification"
echo "=========================================================="

# 1. Syntax validations
check "release.sh syntax" "bash -n scripts/release.sh"
check "release-package.sh syntax" "bash -n scripts/release-package.sh"
check "package-dmg.sh syntax" "bash -n scripts/package-dmg.sh"
check "update-homebrew-tap.sh syntax" "bash -n scripts/update-homebrew-tap.sh"
check "generate-appcast.sh syntax" "bash -n scripts/generate-appcast.sh"
check "verify-pages-staging.sh syntax" "bash -n scripts/verify-pages-staging.sh"

# 2. Release Packager pipeline invariants
check "release-package calls package-dmg.sh" \
    "grep -q 'scripts/package-dmg.sh' scripts/release-package.sh"

check "release-package defines CANONICAL_DMG" \
    "grep -q 'CANONICAL_DMG=' scripts/release-package.sh"

check "release-package notarizes DMG" \
    "grep -q 'xcrun notarytool submit \"\${CANONICAL_DMG}\"' scripts/release-package.sh"

check "release-package staples DMG" \
    "grep -q 'xcrun stapler staple \"\${CANONICAL_DMG}\"' scripts/release-package.sh"

check "release-package validates stapled DMG" \
    "grep -q 'xcrun stapler validate \"\${CANONICAL_DMG}\"' scripts/release-package.sh"

check "release-package writes dual SHA256SUMS (ZIP and DMG)" \
    "grep -B 5 'SUMS_FILE' scripts/release-package.sh | grep -q 'Loom-.*macOS\.zip' && grep -B 5 'SUMS_FILE' scripts/release-package.sh | grep -q 'Loom-.*\.dmg'"

check "release-package preserves ZIP for Homebrew tap sync" \
    "grep -q 'scripts/update-homebrew-tap.sh.*ZIP_SHA' scripts/release-package.sh"

# 3. Release orchestrator prepare & publish invariants
check "release.sh prepare requires both ZIP and DMG" \
    "grep -q '! -f \"\${canonical_zip}\" || ! -f \"\${canonical_dmg}\"' scripts/release.sh"

check "release.sh publish requires both ZIP and DMG" \
    "grep -q 'Required: \${canonical_zip}, \${canonical_dmg}' scripts/release.sh"

check "release.sh publish verifies both ZIP and DMG checksums" \
    "grep -q 'expected_zip_sha=' scripts/release.sh && grep -q 'expected_dmg_sha=' scripts/release.sh"

check "release.sh publish includes DMG in release_assets" \
    "grep -q 'release_assets=(\"\${canonical_zip}\" \"\${canonical_dmg}\"' scripts/release.sh"

check "release.sh publish verifies both uploaded ZIP and DMG" \
    "grep -q 'zip_download_url=' scripts/release.sh && grep -q 'dmg_download_url=' scripts/release.sh"

check "release.sh publish passes ZIP SHA to Homebrew tap" \
    "grep -q 'update-homebrew-tap.sh.*computed_zip_sha' scripts/release.sh"

# 4. Mock checksum generation and verification logic
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/loom-pipeline-probe.XXXXXX")"
trap 'rm -rf "${TEST_TMP}"' EXIT INT TERM

echo "mock zip content" > "${TEST_TMP}/Loom-9.9-macOS.zip"
echo "mock dmg content" > "${TEST_TMP}/Loom-9.9.dmg"

MOCK_ZIP_SHA="$(shasum -a 256 "${TEST_TMP}/Loom-9.9-macOS.zip" | awk '{print $1}')"
MOCK_DMG_SHA="$(shasum -a 256 "${TEST_TMP}/Loom-9.9.dmg" | awk '{print $1}')"

{
    echo "${MOCK_ZIP_SHA}  Loom-9.9-macOS.zip"
    echo "${MOCK_DMG_SHA}  Loom-9.9.dmg"
} > "${TEST_TMP}/SHA256SUMS.txt"

check "dual SHA256SUMS format matches ZIP entry" \
    "[[ \$(grep 'Loom-9.9-macOS.zip' \"${TEST_TMP}/SHA256SUMS.txt\" | awk '{print \$1}') == \"${MOCK_ZIP_SHA}\" ]]"

check "dual SHA256SUMS format matches DMG entry" \
    "[[ \$(grep 'Loom-9.9.dmg' \"${TEST_TMP}/SHA256SUMS.txt\" | awk '{print \$1}') == \"${MOCK_DMG_SHA}\" ]]"

check "dual SHA256SUMS validates via shasum -c" \
    "(cd \"${TEST_TMP}\" && shasum -a 256 -c SHA256SUMS.txt >/dev/null 2>&1)"

check "pages staging simulation and invariants" \
    "bash scripts/verify-pages-staging.sh >/dev/null 2>&1"

rm -rf "${TEST_TMP}"
trap - EXIT INT TERM

echo ""
echo "----------------------------------------------------------"
echo "Probe Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed."
echo "=========================================================="

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    exit 1
fi
