#!/usr/bin/env bash
set -euo pipefail

# Loom macOS DMG packager
# Creates a polished, read-only UDZO disk image with Loom.app and /Applications symlink
# Configures native Finder window geometry, background artwork, and icon positioning.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-${ROOT_DIR}/.build/Loom.app}"
VERSION="${VERSION:-0.1.1}"
DIST_DIR="${ROOT_DIR}/dist"
DMG_NAME="Loom-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DMG_SUPPORT_DIR="${ROOT_DIR}/scripts/dmg"
VOL_NAME="Loom"
MOUNT_DIR="/Volumes/${VOL_NAME}"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Error: App bundle not found at: ${APP_BUNDLE}" >&2
    echo "Usage: $0 [path/to/Loom.app]" >&2
    exit 1
fi

echo "==> Verifying input app bundle signature before packaging..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# Pre-check: Ensure /Volumes/Loom is not already occupied
if [[ -d "${MOUNT_DIR}" ]] || mount | grep -q "on ${MOUNT_DIR} "; then
    echo "Error: Staging mountpoint ${MOUNT_DIR} is already in use." >&2
    echo "Please detach existing ${MOUNT_DIR} volume before packaging." >&2
    exit 1
fi

# State variables for cleanup
CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loom-swift-cache.XXXXXX")"
WORK_DIR=""
STAGING_DMG=""
FINAL_TEMP_DMG=""
TEMP_SHA256_FILE=""
TEMP_SUMS_FILE=""
BACKUP_DIR=""
PUBLISHED=0
MOUNTED=0

cleanup() {
    local exit_code="${1:-$?}"
    # Disable traps to prevent re-entry / recursion
    trap - EXIT INT TERM

    if [[ "${MOUNTED}" -eq 1 ]]; then
        echo "==> Detaching staging volume at ${MOUNT_DIR}..."
        if ! hdiutil detach "${MOUNT_DIR}" -force 2>/dev/null; then
            echo "ERROR: Failed to detach staging volume at ${MOUNT_DIR}." >&2
            echo "Preserving work directory ${WORK_DIR} and staging disk image for manual inspection." >&2
            [[ ${exit_code} -eq 0 ]] && exit_code=1
            exit "${exit_code}"
        fi
        MOUNTED=0
    fi

    if [[ ${exit_code} -eq 0 && -n "${WORK_DIR:-}" && -d "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}" || true
    elif [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR}" ]]; then
        echo "Preserving work directory at ${WORK_DIR} due to failure (exit ${exit_code})." >&2
    fi

    if [[ -n "${CACHE_DIR:-}" && -d "${CACHE_DIR}" ]]; then
        rm -rf "${CACHE_DIR}" || true
    fi

    if [[ -n "${FINAL_TEMP_DMG:-}" && -f "${FINAL_TEMP_DMG}" && ${exit_code} -ne 0 ]]; then
        echo "Cleaning up incomplete temporary DMG: ${FINAL_TEMP_DMG}..."
        rm -f "${FINAL_TEMP_DMG}" || true
    fi

    if [[ -n "${TEMP_SHA256_FILE:-}" && -f "${TEMP_SHA256_FILE}" ]]; then
        rm -f "${TEMP_SHA256_FILE}" || true
    fi

    if [[ -n "${TEMP_SUMS_FILE:-}" && -f "${TEMP_SUMS_FILE}" ]]; then
        rm -f "${TEMP_SUMS_FILE}" || true
    fi

    if [[ ${exit_code} -ne 0 && -n "${BACKUP_DIR:-}" && -d "${BACKUP_DIR}" && "${PUBLISHED}" -eq 0 ]]; then
        echo "Recovering previous distribution artifacts from ${BACKUP_DIR}..." >&2
        if [[ -f "${BACKUP_DIR}/${DMG_NAME}" ]]; then
            if ! cp -p "${BACKUP_DIR}/${DMG_NAME}" "${DMG_PATH}"; then
                echo "ERROR: Failed to restore ${DMG_PATH} from backup." >&2
            fi
        fi
        if [[ -f "${BACKUP_DIR}/${DMG_NAME}.sha256" ]]; then
            if ! cp -p "${BACKUP_DIR}/${DMG_NAME}.sha256" "${DMG_PATH}.sha256"; then
                echo "ERROR: Failed to restore ${DMG_PATH}.sha256 from backup." >&2
            fi
        fi
        if [[ -f "${BACKUP_DIR}/SHA256SUMS.txt" ]]; then
            if ! cp -p "${BACKUP_DIR}/SHA256SUMS.txt" "${DIST_DIR}/SHA256SUMS.txt"; then
                echo "ERROR: Failed to restore SHA256SUMS.txt from backup." >&2
            fi
        fi
    fi

    exit "${exit_code}"
}

# Install separate traps immediately after first temp allocation
trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

# Ensure all background assets (1x, 2x, TIFF) are present
if [[ ! -f "${DMG_SUPPORT_DIR}/background.png" || ! -f "${DMG_SUPPORT_DIR}/background@2x.png" || ! -f "${DMG_SUPPORT_DIR}/background.tiff" ]]; then
    echo "==> Generating background assets..."
    swift -module-cache-path "${CACHE_DIR}" "${DMG_SUPPORT_DIR}/generate-background.swift"
fi

for req_asset in "${DMG_SUPPORT_DIR}/background.png" "${DMG_SUPPORT_DIR}/background@2x.png" "${DMG_SUPPORT_DIR}/background.tiff"; do
    if [[ ! -f "${req_asset}" ]]; then
        echo "Error: Required background asset missing: ${req_asset}" >&2
        exit 1
    fi
done

mkdir -p "${DIST_DIR}"

# Compute staging image size dynamically based on input bundle, background assets, and HFS+ slack
APP_SIZE_KB=$(du -sk "${APP_BUNDLE}" | cut -f1)
BG_SIZE_KB=0
if [[ -d "${DMG_SUPPORT_DIR}" ]]; then
    BG_SIZE_KB=$(du -sk "${DMG_SUPPORT_DIR}" | cut -f1)
fi
TOTAL_PAYLOAD_KB=$(( APP_SIZE_KB + BG_SIZE_KB + 25600 )) # +25MB slack for filesystem structures & icon cache
STAGING_SIZE_MB=$(( (TOTAL_PAYLOAD_KB + 1023) / 1024 ))
if (( STAGING_SIZE_MB < 35 )); then
    STAGING_SIZE_MB=35
fi

# Allocate dedicated private work directory in TMPDIR for staging disk image
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loom-dmg-work.XXXXXX")"
WORK_DIR="$(cd "${WORK_DIR}" && pwd -P)"
STAGING_DMG="${WORK_DIR}/staging.dmg"
FINAL_TEMP_DMG="${DIST_DIR}/.Loom-${VERSION}-$$.tmp.dmg"

echo "==> Creating temporary writable staging image (${STAGING_SIZE_MB} MB)..."
hdiutil create \
    -size "${STAGING_SIZE_MB}m" \
    -fs HFS+ \
    -volname "${VOL_NAME}" \
    -ov \
    "${STAGING_DMG}" >/dev/null

echo "==> Mounting staging image at ${MOUNT_DIR}..."
hdiutil attach "${STAGING_DMG}" -noautoopen -mountpoint "${MOUNT_DIR}" >/dev/null
MOUNTED=1

echo "==> Staging application bundle and background assets..."
ditto "${APP_BUNDLE}" "${MOUNT_DIR}/Loom.app"

echo "==> Verifying staged application bundle signature..."
codesign --verify --deep --strict --verbose=2 "${MOUNT_DIR}/Loom.app"

ln -s /Applications "${MOUNT_DIR}/Applications"

mkdir -p "${MOUNT_DIR}/.background"
cp "${DMG_SUPPORT_DIR}/background.tiff" "${MOUNT_DIR}/.background/background.tiff"
cp "${DMG_SUPPORT_DIR}/background.png" "${MOUNT_DIR}/.background/background.png"
cp "${DMG_SUPPORT_DIR}/background@2x.png" "${MOUNT_DIR}/.background/background@2x.png"

echo "==> Verifying staged background asset hashes match source..."
for bg_file in background.tiff background.png background@2x.png; do
    src_hash=$(shasum -a 256 "${DMG_SUPPORT_DIR}/${bg_file}" | cut -d ' ' -f 1)
    stg_hash=$(shasum -a 256 "${MOUNT_DIR}/.background/${bg_file}" | cut -d ' ' -f 1)
    if [[ "${src_hash}" != "${stg_hash}" ]]; then
        echo "ERROR: Staged background asset hash mismatch for ${bg_file}" >&2
        exit 1
    fi
done

# Hide .background folder if SetFile is available
SetFile -a V "${MOUNT_DIR}/.background" 2>/dev/null || true

# Preserve any pre-existing root metadata into WORK_DIR before fresh Finder configuration
if [[ -f "${MOUNT_DIR}/.DS_Store" ]]; then
    echo "==> Preserving pre-existing .DS_Store to ${WORK_DIR}/pre-existing.DS_Store..."
    mv -f "${MOUNT_DIR}/.DS_Store" "${WORK_DIR}/pre-existing.DS_Store"
fi

# Apply Finder layout: prefer pre-validated template .DS_Store if available, else run AppleScript
if [[ -f "${DMG_SUPPORT_DIR}/template.DS_Store" ]]; then
    echo "==> Applying validated .DS_Store template..."
    cp -p "${DMG_SUPPORT_DIR}/template.DS_Store" "${MOUNT_DIR}/.DS_Store"
else
    echo "==> Applying Finder layout via AppleScript..."
    osascript "${DMG_SUPPORT_DIR}/configure-window.applescript" "${VOL_NAME}" "${MOUNT_DIR}"
fi

echo "==> Verifying .DS_Store persistence on staging volume..."
DS_STORE_FOUND=0
for i in {1..10}; do
    if [[ -f "${MOUNT_DIR}/.DS_Store" ]]; then
        DS_STORE_FOUND=1
        echo "Found .DS_Store ($(wc -c < "${MOUNT_DIR}/.DS_Store" | tr -d ' ') bytes) after ${i} attempt(s)."
        break
    fi
    sleep 1
done

if [[ "${DS_STORE_FOUND}" -ne 1 ]]; then
    echo "ERROR: .DS_Store was not generated or flushed to ${MOUNT_DIR}." >&2
    exit 1
fi

echo "==> Verifying .DS_Store background and icon-view properties..."
swift -module-cache-path "${CACHE_DIR}" "${DMG_SUPPORT_DIR}/verify-ds-store.swift" "${MOUNT_DIR}/.DS_Store"

# Ensure all filesystem operations are flushed
sync
sleep 1

echo "==> Detaching staging disk image..."
hdiutil detach "${MOUNT_DIR}" >/dev/null
MOUNTED=0

echo "==> Converting to compressed read-only UDZO image at temporary path..."
rm -f "${FINAL_TEMP_DMG}"
hdiutil convert \
    "${STAGING_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${FINAL_TEMP_DMG}" >/dev/null

echo "==> Verifying disk image structure..."
hdiutil verify "${FINAL_TEMP_DMG}" >/dev/null

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "==> Code signing DMG with identity: ${SIGNING_IDENTITY}..."
    codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${FINAL_TEMP_DMG}"
    echo "==> Verifying DMG signature..."
    codesign --verify --verbose=2 "${FINAL_TEMP_DMG}"
else
    echo "==> SIGNING_IDENTITY not set. DMG created without code signature."
fi

echo "==> Verifying source app bundle signature remains intact after packaging..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# Back up existing distribution artifacts before replacing output
EXISTING_ARTIFACTS=()
for art in "${DMG_PATH}" "${DMG_PATH}.sha256" "${DIST_DIR}/SHA256SUMS.txt"; do
    if [[ -f "${art}" ]]; then
        EXISTING_ARTIFACTS+=("${art}")
    fi
done

if [[ ${#EXISTING_ARTIFACTS[@]} -gt 0 ]]; then
    BACKUP_DIR="${DIST_DIR}/backups/backup-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "${BACKUP_DIR}"
    echo "==> Backing up existing distribution artifacts to ${BACKUP_DIR}..."
    for art in "${EXISTING_ARTIFACTS[@]}"; do
        if ! cp -p "${art}" "${BACKUP_DIR}/"; then
            echo "ERROR: Failed to back up ${art} to ${BACKUP_DIR}." >&2
            exit 1
        fi
    done
fi

echo "==> Pre-computing SHA-256 checksums before publication..."
TEMP_SHA256_FILE="${DIST_DIR}/.Loom-${VERSION}-$$.sha256"
TEMP_SUMS_FILE="${DIST_DIR}/.SHA256SUMS-$$.txt"
STAGE_HASH=$(shasum -a 256 "${FINAL_TEMP_DMG}" | cut -d ' ' -f 1)
echo "${STAGE_HASH}  ${DMG_NAME}" > "${TEMP_SHA256_FILE}"
echo "${STAGE_HASH}  ${DMG_NAME}" > "${TEMP_SUMS_FILE}"

# Verify checksum against temporary stage before publishing
(
    cd "${DIST_DIR}"
    shasum -a 256 -c <(echo "${STAGE_HASH}  $(basename "${FINAL_TEMP_DMG}")") >/dev/null
)

echo "==> Atomically publishing verified DMG and checksum files..."
mv -f "${FINAL_TEMP_DMG}" "${DMG_PATH}"
mv -f "${TEMP_SHA256_FILE}" "${DMG_PATH}.sha256"
mv -f "${TEMP_SUMS_FILE}" "${DIST_DIR}/SHA256SUMS.txt"
PUBLISHED=1

echo "==> Successfully packaged and published DMG: ${DMG_PATH}"
echo "    SHA-256: ${STAGE_HASH}"
