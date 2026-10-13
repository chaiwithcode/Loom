#!/usr/bin/env bash
set -euo pipefail

# Loom — Automated End-to-End Sparkle Upgrade Test
# Verifies: appcast discovery -> EdDSA signature verification -> download -> extraction

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "=========================================================="
echo "Loom Sparkle Upgrade End-to-End Verification"
echo "=========================================================="

export TMPDIR="${ROOT_DIR}/.build/tmp"
mkdir -p "${TMPDIR}"

echo "==> Step 1: Compiling Sparkle test harness..."
mkdir -p .build/ModuleCache
swiftc -parse-as-library -module-cache-path .build/ModuleCache \
    -F .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64 \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -o .build/test-sparkle-runner scripts/test-sparkle-runner.swift

mkdir -p .build/LoomUpgradeTest.app/Contents/MacOS .build/LoomUpgradeTest.app/Contents/Frameworks
cp .build/test-sparkle-runner .build/LoomUpgradeTest.app/Contents/MacOS/LoomUpgradeTest
rm -rf .build/LoomUpgradeTest.app/Contents/Frameworks/Sparkle.framework
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework .build/LoomUpgradeTest.app/Contents/Frameworks/
cat > .build/LoomUpgradeTest.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.chaiwithcode.loom.upgrade-test</string>
    <key>CFBundleExecutable</key>
    <string>LoomUpgradeTest</string>
    <key>CFBundleName</key>
    <string>LoomUpgradeTest</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
codesign --force --sign - .build/LoomUpgradeTest.app/Contents/Frameworks/Sparkle.framework
codesign --force --sign - .build/LoomUpgradeTest.app

echo "==> Step 2: Generating ephemeral Ed25519 keypair for test isolation..."
KEYS="$(swift -module-cache-path .build/ModuleCache -e 'import CryptoKit; import Foundation; let k = Curve25519.Signing.PrivateKey(); print(k.rawRepresentation.base64EncodedString(), k.publicKey.rawRepresentation.base64EncodedString())')"
TEST_PRIV="$(echo "${KEYS}" | awk '{print $1}')"
TEST_PUB="$(echo "${KEYS}" | awk '{print $2}')"
echo "    Test Public Key:  ${TEST_PUB}"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loom-sparkle-test.XXXXXX")"
FEED_DIR="${TEST_DIR}/feed"
mkdir -p "${FEED_DIR}"

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        kill "${SERVER_PID}" 2>/dev/null || true
    fi
    rm -rf "${TEST_DIR}"
}
trap cleanup EXIT INT TERM

# Allocate free local port
TEST_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')

sign_app() {
    local target="$1"
    local fw="${target}/Contents/Frameworks/Sparkle.framework"
    if [[ -d "${fw}" ]]; then
        codesign --force --sign - "${fw}/Versions/B/XPCServices/Downloader.xpc"
        codesign --force --sign - "${fw}/Versions/B/XPCServices/Installer.xpc"
        codesign --force --sign - "${fw}/Versions/B/Autoupdate"
        codesign --force --sign - "${fw}/Versions/B/Updater.app"
        codesign --force --sign - "${fw}"
    fi
    codesign --force --sign - "${target}"
}

echo "==> Step 3: Staging Loom v0.1.0 (base installed app)..."
cp -R ".build/Loom.app" "${TEST_DIR}/Loom-0.1.0.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.0" "${TEST_DIR}/Loom-0.1.0.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "${TEST_DIR}/Loom-0.1.0.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL http://127.0.0.1:${TEST_PORT}/appcast.xml" "${TEST_DIR}/Loom-0.1.0.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${TEST_PUB}" "${TEST_DIR}/Loom-0.1.0.app/Contents/Info.plist"
sign_app "${TEST_DIR}/Loom-0.1.0.app"

echo "==> Step 4: Staging Loom v0.1.1 (target upgrade app)..."
cp -R ".build/Loom.app" "${TEST_DIR}/Loom-0.1.1.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.1" "${TEST_DIR}/Loom-0.1.1.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 2" "${TEST_DIR}/Loom-0.1.1.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL http://127.0.0.1:${TEST_PORT}/appcast.xml" "${TEST_DIR}/Loom-0.1.1.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${TEST_PUB}" "${TEST_DIR}/Loom-0.1.1.app/Contents/Info.plist"
echo "Loom v0.1.1 upgrade payload" > "${TEST_DIR}/Loom-0.1.1.app/Contents/Resources/upgrade_marker.txt"
sign_app "${TEST_DIR}/Loom-0.1.1.app"

echo "==> Step 5: Packaging and signing upgrade archive..."
mv "${TEST_DIR}/Loom-0.1.1.app" "${TEST_DIR}/Loom.app"
ditto -c -k --keepParent "${TEST_DIR}/Loom.app" "${FEED_DIR}/Loom-0.1.1-macOS.zip"

BIN_DIR="$("${ROOT_DIR}/scripts/fetch-sparkle-tools.sh")"
printf '%s' "${TEST_PRIV}" | "${BIN_DIR}/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "http://127.0.0.1:${TEST_PORT}/" \
    -o "${FEED_DIR}/appcast.xml" \
    "${FEED_DIR}"

echo "==> Generated Appcast Feed:"
cat "${FEED_DIR}/appcast.xml"

echo "==> Step 6: Starting local mock update feed server on port ${TEST_PORT}..."
python3 -m http.server "${TEST_PORT}" --bind 127.0.0.1 -d "${FEED_DIR}" > "${TEST_DIR}/http.log" 2>&1 &
SERVER_PID=$!
sleep 1

echo "==> Step 7: Running Sparkle upgrade lifecycle verification..."
.build/LoomUpgradeTest.app/Contents/MacOS/LoomUpgradeTest "${TEST_DIR}/Loom-0.1.0.app"

echo "==> Step 8: Verifying EdDSA security enforcement (tampered payload rejection)..."
# Corrupt archive payload without updating the signature
echo "MALICIOUS_PAYLOAD_CORRUPTION" >> "${FEED_DIR}/Loom-0.1.1-macOS.zip"

.build/LoomUpgradeTest.app/Contents/MacOS/LoomUpgradeTest "${TEST_DIR}/Loom-0.1.0.app" --expect-failure

echo "=========================================================="
echo "SUCCESS: Sparkle 2 upgrade pipeline & security verified end-to-end!"
echo "=========================================================="
