#!/usr/bin/env bash
set -euo pipefail

# Loom macOS app bundle packager
# Builds Loom release binary and creates .build/Loom.app with LSUIElement=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "==> Building Loom (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE="${BIN_PATH}/Loom"

if [[ ! -f "${EXECUTABLE}" ]]; then
    echo "Error: Executable not found at ${EXECUTABLE}" >&2
    exit 1
fi

APP_BUNDLE="${ROOT_DIR}/.build/Loom.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Packaging ${APP_BUNDLE}..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Atomically stage binary to avoid overwriting running inodes
TMP_BIN="$(mktemp "${MACOS_DIR}/Loom.tmp.XXXXXX")"
trap 'rm -f "${TMP_BIN}"' EXIT INT TERM
cp "${EXECUTABLE}" "${TMP_BIN}"
chmod +x "${TMP_BIN}"
mv -f "${TMP_BIN}" "${MACOS_DIR}/Loom"
trap - EXIT INT TERM

if [[ -f "${ROOT_DIR}/Resources/Loom.icns" ]]; then
    cp "${ROOT_DIR}/Resources/Loom.icns" "${RESOURCES_DIR}/Loom.icns"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Loom</string>
    <key>CFBundleIconFile</key>
    <string>Loom</string>
    <key>CFBundleIdentifier</key>
    <string>com.chaiwithcode.loom</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Loom</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Validating Info.plist..."
plutil -lint "${CONTENTS_DIR}/Info.plist"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "==> Code signing bundle with identity: ${SIGNING_IDENTITY} (Hardened Runtime)..."
    codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
    echo "==> Code signing bundle (ad-hoc with Hardened Runtime)..."
    codesign --force --options runtime --sign - "${APP_BUNDLE}"
fi

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Successfully packaged Loom.app at: ${APP_BUNDLE}"
