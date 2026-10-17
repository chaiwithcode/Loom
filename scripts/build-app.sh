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

PLUGINS_DIR="${CONTENTS_DIR}/PlugIns"
WIDGET_APPEX="${PLUGINS_DIR}/LoomWidgetExtension.appex"

echo "==> Packaging ${APP_BUNDLE}..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}" "${PLUGINS_DIR}"

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

# Build and stage LoomWidgetExtension using Xcode native target
echo "==> Building LoomWidgetExtension using Xcode native target..."
XCODE_BUILD_DIR="${ROOT_DIR}/.build/xcode"
mkdir -p "${XCODE_BUILD_DIR}"
xcodebuild build \
    -project "${ROOT_DIR}/Loom.xcodeproj" \
    -scheme LoomWidgetExtension \
    -destination 'platform=macOS' \
    -configuration Release \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "${XCODE_BUILD_DIR}"

WIDGET_BUILD_APPEX="${XCODE_BUILD_DIR}/Build/Products/Release/LoomWidgetExtension.appex"
if [[ ! -d "${WIDGET_BUILD_APPEX}" ]]; then
    echo "Error: LoomWidgetExtension.appex not found at ${WIDGET_BUILD_APPEX}" >&2
    exit 1
fi

echo "==> Staging LoomWidgetExtension into Contents/PlugIns..."
rm -rf "${WIDGET_APPEX}"
cp -R "${WIDGET_BUILD_APPEX}" "${WIDGET_APPEX}"

if [[ -f "${ROOT_DIR}/Resources/Loom.icns" ]]; then
    cp "${ROOT_DIR}/Resources/Loom.icns" "${RESOURCES_DIR}/Loom.icns"
fi

for asset in "${ROOT_DIR}/Resources/provider-"*.png; do
    if [[ -f "${asset}" ]]; then
        cp "${asset}" "${RESOURCES_DIR}/"
    fi
done

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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>4</string>
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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.chaiwithcode.loom</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>loom</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "==> Validating Info.plist..."
plutil -lint "${CONTENTS_DIR}/Info.plist"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    DETECTED_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o 'Developer ID Application: [^"]*' | head -n 1 || true)"
    if [[ -z "${DETECTED_ID}" ]]; then
        DETECTED_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o 'Apple Development: [^"]*' | head -n 1 || true)"
    fi
    if [[ -n "${DETECTED_ID}" ]]; then
        SIGNING_IDENTITY="${DETECTED_ID}"
        echo "==> Auto-detected signing identity: ${SIGNING_IDENTITY}"
    fi
fi

sign_component() {
    local target="$1"
    local entitlements="${2:-}"
    local sign_cmd=(codesign --force)
    if [[ -n "${entitlements}" && -f "${entitlements}" ]]; then
        sign_cmd+=(--entitlements "${entitlements}")
    fi
    if [[ -n "${SIGNING_IDENTITY}" ]]; then
        sign_cmd+=(--options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${target}")
    else
        sign_cmd+=(--sign - "${target}")
    fi
    "${sign_cmd[@]}"
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

# Code sign embedded LoomWidgetExtension
if [[ -d "${WIDGET_APPEX}" ]]; then
    echo "==> Code signing LoomWidgetExtension.appex inside-out..."
    sign_component "${WIDGET_APPEX}" "${ROOT_DIR}/LoomWidget/LoomWidget.entitlements"
fi

if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "==> Code signing app bundle with identity: ${SIGNING_IDENTITY} (Hardened Runtime)..."
else
    echo "==> Code signing app bundle (ad-hoc with Hardened Runtime)..."
fi
sign_component "${APP_BUNDLE}" "${ROOT_DIR}/Loom.entitlements"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Successfully packaged Loom.app at: ${APP_BUNDLE}"
