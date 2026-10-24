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
check "release.sh preflight counters avoid set-e postincrement"     "! grep -Eq '\\(\\((pass_count|warn_count|fail_count|attempt)\+\+\)\\)' scripts/release.sh && grep -q 'pass_count=\$((pass_count + 1))' scripts/release.sh"
check "publish readiness gate runs before release mutations" \
    "[[ \$(grep -c 'public_release_preflight' scripts/release.sh) -eq 2 ]] && grep -q -- '--verify-tag' scripts/release.sh && ! grep -q -- '--clobber' scripts/release.sh"
check "GitHub release commands target chaiwithcode/Loom explicitly" \
    "awk '/gh release (view|create|upload|edit)/ { if (\$0 ~ /--repo chaiwithcode\/Loom/) next; if (\$0 ~ /gh release create/) { pending=3; next } bad=1 } pending > 0 { if (\$0 ~ /--repo chaiwithcode\/Loom/) pending=0; else pending-- } END { exit bad || pending }' scripts/release.sh"
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
check "release-package refuses to overwrite a canonical ZIP" \
    "grep -q 'Canonical ZIP already exists' scripts/release-package.sh"
check "Homebrew sync requires explicit --sync, not token presence" \
    "grep -q '^SYNC_TAP=0' scripts/update-homebrew-tap.sh && awk '/^if \\[\\[.*SYNC_TAP/ { if (\$0 ~ /HOMEBREW_TAP_TOKEN/) bad=1 } END { exit bad }' scripts/update-homebrew-tap.sh"

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

# 4. Run the real --check path with mocked tools to prove counters reach the summary under set -e.
CHECK_FIXTURE="${TEST_TMP}/check-fixture"
CHECK_BIN="${TEST_TMP}/check-bin"
mkdir -p "${CHECK_FIXTURE}/scripts" "${CHECK_FIXTURE}/Resources" "${CHECK_BIN}"
cp scripts/release.sh "${CHECK_FIXTURE}/scripts/release.sh"
cp scripts/build-app.sh "${CHECK_FIXTURE}/scripts/build-app.sh"
cp Resources/Info.plist "${CHECK_FIXTURE}/Resources/Info.plist"
cat > "${CHECK_FIXTURE}/scripts/fetch-sparkle-tools.sh" <<'MOCK'
#!/bin/sh
printf '%s/mock-bin\n' "$(cd "$(dirname "$0")/.." && pwd)"
MOCK
chmod +x "${CHECK_FIXTURE}/scripts/fetch-sparkle-tools.sh"
mkdir -p "${CHECK_FIXTURE}/mock-bin"
cat > "${CHECK_FIXTURE}/mock-bin/generate_keys" <<'MOCK'
#!/bin/sh
printf 'jFxPCf9cSvpmuEc6U4EdjWlYwMzMVlTd6M8wPlvLZsE=\n'
MOCK
chmod +x "${CHECK_FIXTURE}/mock-bin/generate_keys"
cat > "${CHECK_BIN}/security" <<'MOCK'
#!/bin/sh
if [ "$1" = find-identity ]; then echo '1) ABC "Developer ID Application: Probe (TEAMID)"'; fi
exit 0
MOCK
cat > "${CHECK_BIN}/gh" <<'MOCK'
#!/bin/sh
if [ "$1" = api ]; then echo probe; fi
exit 0
MOCK
for tool in swift codesign xcrun ditto shasum brew; do
    cat > "${CHECK_BIN}/${tool}" <<'MOCK'
#!/bin/sh
exit 0
MOCK
    chmod +x "${CHECK_BIN}/${tool}"
done
chmod +x "${CHECK_BIN}/security" "${CHECK_BIN}/gh"
git -c init.defaultBranch=main init -q "${CHECK_FIXTURE}/repo"
git -C "${CHECK_FIXTURE}/repo" config user.email probe@example.invalid
git -C "${CHECK_FIXTURE}/repo" config user.name probe
cp -R "${CHECK_FIXTURE}/scripts" "${CHECK_FIXTURE}/repo/"
cp -R "${CHECK_FIXTURE}/Resources" "${CHECK_FIXTURE}/repo/"
cp -R "${CHECK_FIXTURE}/mock-bin" "${CHECK_FIXTURE}/repo/"
git -C "${CHECK_FIXTURE}/repo" add .
git -C "${CHECK_FIXTURE}/repo" commit -qm fixture
if (cd "${CHECK_FIXTURE}/repo" && PATH="${CHECK_BIN}:${PATH}" bash scripts/release.sh --check) >"${TEST_TMP}/check-output.log" 2>&1 && \
   grep -q '0 failures' "${TEST_TMP}/check-output.log" && grep -q 'Status: System is READY' "${TEST_TMP}/check-output.log"; then
    echo "Checking mocked --check reaches its full audit summary... [PASS]"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "Checking mocked --check reaches its full audit summary... [FAIL]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Prove an inherited tap token cannot cause Homebrew sync or tracked Cask edits.
TAP_FIXTURE="${TEST_TMP}/tap-fixture"
mkdir -p "${TAP_FIXTURE}/scripts" "${TAP_FIXTURE}/homebrew-tap/Casks" "${TAP_FIXTURE}/dist" "${TAP_FIXTURE}/bin"
cat > "${TAP_FIXTURE}/bin/gh" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "${GH_LOG}"
exit 0
MOCK
chmod +x "${TAP_FIXTURE}/bin/gh"
cp scripts/update-homebrew-tap.sh "${TAP_FIXTURE}/scripts/update-homebrew-tap.sh"
printf 'tracked cask before prepare\n' > "${TAP_FIXTURE}/homebrew-tap/Casks/chaiwithcode-loom.rb"
TAP_BEFORE="$(shasum -a 256 "${TAP_FIXTURE}/homebrew-tap/Casks/chaiwithcode-loom.rb" | awk '{print $1}')"
if (cd "${TAP_FIXTURE}" && HOMEBREW_TAP_TOKEN=probe GH_LOG="${TEST_TMP}/tap-gh.log" PATH="${TAP_FIXTURE}/bin:${PATH}" bash scripts/update-homebrew-tap.sh 9.9 "${MOCK_ZIP_SHA}") >"${TEST_TMP}/tap-token.out" 2>&1 && \
   [[ "${TAP_BEFORE}" == "$(shasum -a 256 "${TAP_FIXTURE}/homebrew-tap/Casks/chaiwithcode-loom.rb" | awk '{print $1}')" ]] && \
   [[ -f "${TAP_FIXTURE}/dist/chaiwithcode-loom.rb" ]] && [[ ! -s "${TEST_TMP}/tap-gh.log" ]]; then
    echo "Checking token-only Homebrew preparation stays local... [PASS]"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "Checking token-only Homebrew preparation stays local... [FAIL]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# 5. Offline refusal scenarios: an existing versioned ZIP and an existing public release.
PACKAGE_FIXTURE="${TEST_TMP}/package-fixture"
mkdir -p "${PACKAGE_FIXTURE}/scripts" "${PACKAGE_FIXTURE}/dist"
cp scripts/release-package.sh "${PACKAGE_FIXTURE}/scripts/release-package.sh"
printf 'original immutable artifact\n' > "${PACKAGE_FIXTURE}/dist/Loom-9.9-macOS.zip"
if bash "${PACKAGE_FIXTURE}/scripts/release-package.sh" 9.9 >"${TEST_TMP}/immutable.out" 2>&1; then
    echo "Checking existing canonical ZIP refusal... [FAIL]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
elif grep -q 'Refusing to replace an immutable versioned artifact' "${TEST_TMP}/immutable.out" && \
     grep -q 'original immutable artifact' "${PACKAGE_FIXTURE}/dist/Loom-9.9-macOS.zip"; then
    echo "Checking existing canonical ZIP refusal... [PASS]"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "Checking existing canonical ZIP refusal... [FAIL]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

PUBLISH_FIXTURE="${TEST_TMP}/publish-fixture"
MOCK_BIN="${TEST_TMP}/mock-bin"
mkdir -p "${PUBLISH_FIXTURE}/scripts" "${PUBLISH_FIXTURE}/.build/Loom.app" "${PUBLISH_FIXTURE}/dist" "${MOCK_BIN}"
cp scripts/build-app.sh "${PUBLISH_FIXTURE}/scripts/build-app.sh"
grep -A 1 'CFBundleShortVersionString' scripts/build-app.sh > "${PUBLISH_FIXTURE}/scripts/build-app.sh"
# Ensure the copied minimal version file remains parseable by the preflight.
if ! grep -q '<string>' "${PUBLISH_FIXTURE}/scripts/build-app.sh"; then
    printf '<key>CFBundleShortVersionString</key>\n<string>9.9</string>\n' > "${PUBLISH_FIXTURE}/scripts/build-app.sh"
else
    sed -i.bak 's/<string>[^<]*<\/string>/<string>9.9<\/string>/' "${PUBLISH_FIXTURE}/scripts/build-app.sh"
    rm -f "${PUBLISH_FIXTURE}/scripts/build-app.sh.bak"
fi
printf 'mock zip\n' > "${PUBLISH_FIXTURE}/dist/Loom-9.9-macOS.zip"
printf 'mock dmg\n' > "${PUBLISH_FIXTURE}/dist/Loom-9.9.dmg"
ZIP_HASH="$(shasum -a 256 "${PUBLISH_FIXTURE}/dist/Loom-9.9-macOS.zip" | awk '{print $1}')"
DMG_HASH="$(shasum -a 256 "${PUBLISH_FIXTURE}/dist/Loom-9.9.dmg" | awk '{print $1}')"
printf '%s  Loom-9.9-macOS.zip\n%s  Loom-9.9.dmg\n' "${ZIP_HASH}" "${DMG_HASH}" > "${PUBLISH_FIXTURE}/dist/SHA256SUMS.txt"
git init -q "${PUBLISH_FIXTURE}/repo"
git -C "${PUBLISH_FIXTURE}/repo" config user.email probe@example.invalid
git -C "${PUBLISH_FIXTURE}/repo" config user.name probe
git -C "${PUBLISH_FIXTURE}/repo" remote add origin "${PUBLISH_FIXTURE}/remote.git"
git init --bare -q "${PUBLISH_FIXTURE}/remote.git"
mkdir -p "${PUBLISH_FIXTURE}/repo/scripts" "${PUBLISH_FIXTURE}/repo/.build/Loom.app" "${PUBLISH_FIXTURE}/repo/dist"
cp "${PUBLISH_FIXTURE}/scripts/build-app.sh" "${PUBLISH_FIXTURE}/repo/scripts/build-app.sh"
cp -R "${PUBLISH_FIXTURE}/.build/Loom.app" "${PUBLISH_FIXTURE}/repo/.build/"
cp "${PUBLISH_FIXTURE}/dist/"* "${PUBLISH_FIXTURE}/repo/dist/"
printf 'fixture\n' > "${PUBLISH_FIXTURE}/repo/fixture.txt"
git -C "${PUBLISH_FIXTURE}/repo" add .
git -C "${PUBLISH_FIXTURE}/repo" commit -qm fixture
awk '/^public_release_preflight\(\) \{/{copy=1} /^# Mode 3: Publish Release/{copy=0} copy {print}' scripts/release.sh > "${PUBLISH_FIXTURE}/repo/preflight.sh"
cat > "${MOCK_BIN}/codesign" <<'MOCK'
#!/bin/sh
case "$1" in
  -dv) echo 'Authority=Developer ID Application: Probe (TEAMID)' >&2; echo 'flags=0x10000(runtime)' >&2 ;;
esac
exit 0
MOCK
cat > "${MOCK_BIN}/xcrun" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "${MOCK_BIN}/spctl" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "${MOCK_BIN}/gh" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "${GH_LOG}"
exit 0
MOCK
chmod +x "${MOCK_BIN}/"*
cat > "${PUBLISH_FIXTURE}/repo/run-preflight.sh" <<'MOCK'
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(pwd)"
source ./preflight.sh
public_release_preflight 9.9
MOCK
chmod +x "${PUBLISH_FIXTURE}/repo/run-preflight.sh"
git -C "${PUBLISH_FIXTURE}/repo" add preflight.sh run-preflight.sh
git -C "${PUBLISH_FIXTURE}/repo" commit -qm probe
if (cd "${PUBLISH_FIXTURE}/repo" && GH_LOG="${TEST_TMP}/gh.log" PATH="${MOCK_BIN}:${PATH}" ./run-preflight.sh) >"${TEST_TMP}/publish-refusal.out" 2>&1; then
    echo "Checking existing GitHub release refusal... [FAIL]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
elif grep -q 'GitHub Release v9.9 already exists' "${TEST_TMP}/publish-refusal.out" && \
     [[ -z "$(git -C "${PUBLISH_FIXTURE}/repo" tag --list)" ]] && \
     [[ -z "$(git --git-dir="${PUBLISH_FIXTURE}/remote.git" show-ref)" ]]; then
    echo "Checking existing GitHub release refusal before tag mutation... [PASS]"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "Checking existing GitHub release refusal before tag mutation... [FAIL]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

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
