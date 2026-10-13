#!/usr/bin/env bash
set -euo pipefail

# Loom — Fetch and verify official Sparkle 2 release tooling
# Downloads pinned Sparkle release tools matching SPM dependency.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="2.10.0"
EXPECTED_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

TOOLS_DIR="${ROOT_DIR}/.build/tools/sparkle-${SPARKLE_VERSION}"
BIN_DIR="${TOOLS_DIR}/bin"

if [[ -x "${BIN_DIR}/generate_appcast" && -x "${BIN_DIR}/generate_keys" && -x "${BIN_DIR}/sign_update" ]]; then
    echo "${BIN_DIR}"
    exit 0
fi

mkdir -p "${TOOLS_DIR}"
ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
TMP_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/Sparkle-${SPARKLE_VERSION}.XXXXXX.tar.xz")"
trap 'rm -f "${TMP_ARCHIVE}"' EXIT INT TERM

echo "==> Downloading Sparkle ${SPARKLE_VERSION} tools..." >&2
curl -fsSL "${ARCHIVE_URL}" -o "${TMP_ARCHIVE}"

echo "==> Verifying checksum..." >&2
ACTUAL_SHA256=$(shasum -a 256 "${TMP_ARCHIVE}" | awk '{print $1}')
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
    echo "ERROR: Checksum mismatch for Sparkle tools archive!" >&2
    echo "Expected: ${EXPECTED_SHA256}" >&2
    echo "Actual:   ${ACTUAL_SHA256}" >&2
    exit 1
fi

echo "==> Extracting tools to ${TOOLS_DIR}..." >&2
tar -xJ -C "${TOOLS_DIR}" -f "${TMP_ARCHIVE}"

chmod +x "${BIN_DIR}/generate_appcast" "${BIN_DIR}/generate_keys" "${BIN_DIR}/sign_update"

echo "==> Sparkle tools ready at ${BIN_DIR}" >&2
echo "${BIN_DIR}"
