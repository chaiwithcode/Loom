#!/usr/bin/env bash
set -euo pipefail

# Loom — Canonical Release Packager & Verification Pipeline
# Produces exactly one canonical signed + notarized Loom-X.Y.Z-macOS.zip per release.
# Used by: GitHub Releases, Sparkle 2 appcast, and Homebrew Cask.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Load optional local release configuration
if [[ -f "${ROOT_DIR}/.release.local" ]]; then
    # shellcheck source=/dev/null
    source "${ROOT_DIR}/.release.local"
fi

VERSION="${1:-${VERSION:-1.0}}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
for arg in "$@"; do
    if [[ "${arg}" == "--skip-notarization" ]]; then
        SKIP_NOTARIZATION=1
    fi
done

DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${ROOT_DIR}/.build/Loom.app"
CANONICAL_ZIP="${DIST_DIR}/Loom-${VERSION}-macOS.zip"
CANONICAL_SHA="${CANONICAL_ZIP}.sha256"
SUMS_FILE="${DIST_DIR}/SHA256SUMS.txt"
APPCAST_FILE="${DIST_DIR}/appcast.xml"

mkdir -p "${DIST_DIR}"

if [[ ! -f "${DIST_DIR}/RELEASE_NOTES_v${VERSION}.md" && -f "${ROOT_DIR}/docs/RELEASE_NOTES_v${VERSION}.md" ]]; then
    cp -p "${ROOT_DIR}/docs/RELEASE_NOTES_v${VERSION}.md" "${DIST_DIR}/RELEASE_NOTES_v${VERSION}.md"
fi

echo "=========================================================="
echo "Loom Release Packaging Pipeline — Version ${VERSION}"
echo "=========================================================="

# Auto-detect Developer ID signing identity if not set
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -n "${SIGNING_IDENTITY}" ]]; then
        echo "==> Auto-detected Developer ID identity: ${SIGNING_IDENTITY}"
    fi
fi
export SIGNING_IDENTITY

# Default notarization profile to AC_PASSWORD if credentials not explicitly specified
if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
    NOTARY_PROFILE=""
else
    NOTARY_PROFILE="${NOTARY_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-AC_PASSWORD}}"
fi
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"
NOTARY_KEY_FILE="${NOTARY_KEY_FILE:-}"

# Step 1: Preflight version validations
echo "==> Step 1: Running preflight version checks..."
MARKETING_VER="$(grep -A 1 'CFBundleShortVersionString' scripts/build-app.sh | grep '<string>' | sed -E 's/.*<string>(.*)<\/string>.*/\1/')"
if [[ "${MARKETING_VER}" != "${VERSION}" ]]; then
    echo "ERROR: Version mismatch between request (${VERSION}) and scripts/build-app.sh (${MARKETING_VER})!" >&2
    exit 1
fi

GIT_TAG="${GIT_TAG:-$(git tag --points-at HEAD 2>/dev/null || true)}"
if [[ -n "${GIT_TAG}" && "${GIT_TAG}" != "v${VERSION}" && "${GIT_TAG}" != "${VERSION}" ]]; then
    echo "WARNING: Active git tag (${GIT_TAG}) differs from target version (v${VERSION})" >&2
fi

# Step 2: Build and package Loom.app
echo "==> Step 2: Building and packaging .build/Loom.app..."
bash "${ROOT_DIR}/scripts/build-app.sh"

# Step 3: Notarization & Stapling (if credentials provided)
if [[ -n "${NOTARY_PROFILE}" ]] || [[ -n "${NOTARY_KEY_ID}" && -n "${NOTARY_ISSUER_ID}" && -n "${NOTARY_KEY_FILE}" ]]; then
    echo "==> Step 3: Submitting to Apple Notary Service..."
    SUBMISSION_ZIP="$(mktemp "${TMPDIR:-/tmp}/Loom-notarization-submit.XXXXXX.zip")"
    trap 'rm -f "${SUBMISSION_ZIP}"' EXIT INT TERM
    ditto -c -k --keepParent "${APP_BUNDLE}" "${SUBMISSION_ZIP}"

    if [[ -n "${NOTARY_PROFILE}" ]]; then
        xcrun notarytool submit "${SUBMISSION_ZIP}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            --wait
    else
        xcrun notarytool submit "${SUBMISSION_ZIP}" \
            --key "${NOTARY_KEY_FILE}" \
            --key-id "${NOTARY_KEY_ID}" \
            --issuer "${NOTARY_ISSUER_ID}" \
            --wait
    fi
    rm -f "${SUBMISSION_ZIP}"
    trap - EXIT INT TERM

    echo "==> Step 3.1: Stapling notarization ticket to ${APP_BUNDLE}..."
    xcrun stapler staple "${APP_BUNDLE}"

    echo "==> Step 3.2: Validating stapled ticket..."
    xcrun stapler validate "${APP_BUNDLE}"

    echo "==> Step 3.3: Evaluating Gatekeeper policy acceptance..."
    spctl --assess -vv --type execute "${APP_BUNDLE}"
else
    echo "==> Step 3: Apple notarization credentials not provided (skipping online notarization submit)."
    if [[ -n "${SIGNING_IDENTITY}" ]]; then
        echo "    NOTE: Production public release requires NOTARY_PROFILE or App Store Connect API key."
    fi
fi

# Step 4: Validate app signature before final archiving
echo "==> Step 4: Strict validation of stapled application bundle..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# Step 5: Package canonical ZIP (MUST contain the stapled app, never mutated afterward)
echo "==> Step 5: Creating canonical release artifact: ${CANONICAL_ZIP}..."
TMP_FINAL_ZIP="$(mktemp "${DIST_DIR}/.Loom-${VERSION}-macOS-$$.tmp.zip")"
ditto -c -k --keepParent "${APP_BUNDLE}" "${TMP_FINAL_ZIP}"
mv -f "${TMP_FINAL_ZIP}" "${CANONICAL_ZIP}"

# Step 6: Compute immutable SHA-256 checksums
echo "==> Step 6: Calculating canonical SHA-256 checksum..."
ACTUAL_SHA=$(shasum -a 256 "${CANONICAL_ZIP}" | awk '{print $1}')
echo "${ACTUAL_SHA}  Loom-${VERSION}-macOS.zip" > "${CANONICAL_SHA}"
echo "${ACTUAL_SHA}  Loom-${VERSION}-macOS.zip" > "${SUMS_FILE}"

echo "    Canonical ZIP SHA-256: ${ACTUAL_SHA}"

# Step 7: Sparkle appcast generation & EdDSA signing
echo "==> Step 7: Generating signed Sparkle appcast..."
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]] || security find-generic-password -s "https://sparkle-project.org" -a "ed25519" >/dev/null 2>&1; then
    bash "${ROOT_DIR}/scripts/generate-appcast.sh" "${VERSION}" "${DIST_DIR}" "${APPCAST_FILE}"
else
    echo "    WARNING: SPARKLE_PRIVATE_KEY not available. Run scripts/generate-appcast.sh once credentials are set."
fi

# Step 8: Stage Homebrew Cask with canonical SHA-256
echo "==> Step 8: Staging Homebrew Cask..."
bash "${ROOT_DIR}/scripts/update-homebrew-tap.sh" "${VERSION}" "${ACTUAL_SHA}"

echo "=========================================================="
echo "Release Packaging Complete!"
echo "Artifact:  ${CANONICAL_ZIP}"
echo "SHA-256:   ${ACTUAL_SHA}"
echo "Checksums: ${SUMS_FILE}"
if [[ -f "${APPCAST_FILE}" ]]; then
    echo "Appcast:   ${APPCAST_FILE}"
fi
echo "Cask:      dist/chaiwithcode-loom.rb"
echo "=========================================================="
