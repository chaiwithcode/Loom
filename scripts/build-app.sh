#!/usr/bin/env bash
set -euo pipefail

# Loom macOS app bundle packager
# Builds Loom release binary and creates .build/Loom.app with LSUIElement=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "==> Building Loom (release)..."
swift build --disable-sandbox -c release

BIN_PATH="$(swift build --disable-sandbox -c release --show-bin-path)"
EXECUTABLE="${BIN_PATH}/Loom"

if [[ ! -f "${EXECUTABLE}" ]]; then
    echo "Error: Executable not found at ${EXECUTABLE}" >&2
    exit 1
fi

APP_BUNDLE="${ROOT_DIR}/.build/Loom.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

echo "==> Packaging ${APP_BUNDLE}..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"

# Atomically stage binary to avoid overwriting running inodes
TMP_BIN="$(mktemp "${MACOS_DIR}/Loom.tmp.XXXXXX")"
trap 'rm -f "${TMP_BIN}"' EXIT INT TERM
cp "${EXECUTABLE}" "${TMP_BIN}"
chmod +x "${TMP_BIN}"
mv -f "${TMP_BIN}" "${MACOS_DIR}/Loom"
trap - EXIT INT TERM

# Ensure rpath points to Frameworks
if ! otool -l "${MACOS_DIR}/Loom" | grep -A 2 LC_RPATH | grep -q "@executable_path/../Frameworks"; then
    echo "==> Adding @executable_path/../Frameworks rpath..."
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/Loom"
fi

# Stage Sparkle framework if present in build output
if [[ -d "${BIN_PATH}/Sparkle.framework" ]]; then
    echo "==> Staging Sparkle.framework into Contents/Frameworks..."
    rm -rf "${FRAMEWORKS_DIR}/Sparkle.framework"
    cp -R "${BIN_PATH}/Sparkle.framework" "${FRAMEWORKS_DIR}/Sparkle.framework"
fi

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
    <string>0.1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://chaiwithcode.github.io/Loom/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>jFxPCf9cSvpmuEc6U4EdjWlYwMzMVlTd6M8wPlvLZsE=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Validating Info.plist..."
plutil -lint "${CONTENTS_DIR}/Info.plist"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

sign_component() {
    local target="$1"
    if [[ -n "${SIGNING_IDENTITY}" ]]; then
        codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${target}"
    else
        codesign --force --sign - "${target}"
    fi
}

# Sign nested components inside-out
SPARKLE_FW="${FRAMEWORKS_DIR}/Sparkle.framework"
if [[ -d "${SPARKLE_FW}" ]]; then
    echo "==> Code signing nested Sparkle components inside-out..."
    if [[ -d "${SPARKLE_FW}/Versions/B/XPCServices/Downloader.xpc" ]]; then
        sign_component "${SPARKLE_FW}/Versions/B/XPCServices/Downloader.xpc"
    fi
    if [[ -d "${SPARKLE_FW}/Versions/B/XPCServices/Installer.xpc" ]]; then
        sign_component "${SPARKLE_FW}/Versions/B/XPCServices/Installer.xpc"
    fi
    if [[ -d "${SPARKLE_FW}/Versions/B/Updater.app" ]]; then
        sign_component "${SPARKLE_FW}/Versions/B/Updater.app"
    fi
    if [[ -f "${SPARKLE_FW}/Versions/B/Autoupdate" ]]; then
        sign_component "${SPARKLE_FW}/Versions/B/Autoupdate"
    fi
    sign_component "${SPARKLE_FW}"
fi

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "==> Code signing app bundle with identity: ${SIGNING_IDENTITY} (Hardened Runtime)..."
else
    echo "==> Code signing app bundle (ad-hoc with Hardened Runtime)..."
fi
sign_component "${APP_BUNDLE}"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Successfully packaged Loom.app at: ${APP_BUNDLE}"
