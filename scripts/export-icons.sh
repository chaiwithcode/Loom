#!/usr/bin/env bash
set -euo pipefail

# The approved high-resolution PNG is the source of truth.
# Export with macOS sips and iconutil; no app runtime dependency is introduced.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v sips >/dev/null
command -v iconutil >/dev/null
SOURCE="${ROOT_DIR}/Resources/LoomIconMaster.png"
BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loom-icon-export-backup.XXXXXX")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loom-icon-export.XXXXXX")"
ICONSET="${WORK_DIR}/Loom.iconset"
mkdir -p "${ICONSET}" "${ROOT_DIR}/Resources"

for asset in "${ROOT_DIR}/loom-icon.png" "${ROOT_DIR}/Resources/Loom.icns"; do
    if [[ -f "${asset}" ]]; then cp -p "${asset}" "${BACKUP_DIR}/"; fi
done

while read -r points scale; do
    pixels=$((points * scale))
    suffix=""
    if [[ "${scale}" == 2 ]]; then suffix="@2x"; fi
    sips -z "${pixels}" "${pixels}" "${SOURCE}" \
        --out "${ICONSET}/icon_${points}x${points}${suffix}.png" >/dev/null
done <<'SIZES'
16 1
16 2
32 1
32 2
128 1
128 2
256 1
256 2
512 1
512 2
SIZES

iconutil -c icns "${ICONSET}" -o "${WORK_DIR}/Loom.icns"
cp "${WORK_DIR}/Loom.icns" "${ROOT_DIR}/Resources/Loom.icns"
cp "${ICONSET}/icon_512x512@2x.png" "${ROOT_DIR}/loom-icon.png"
printf 'Exported Loom icon. Originals: %s\nRepresentations: %s\n' "${BACKUP_DIR}" "${ICONSET}"
