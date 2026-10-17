#!/usr/bin/env bash
set -euo pipefail

# Loom — macOS Widget Package & Entitlements Verifier
# Validates widget extension embedding, bundle identity, App Group entitlements, and code signing.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

APP_BUNDLE="${1:-${ROOT_DIR}/.build/Loom.app}"
PLUGINS_DIR="${APP_BUNDLE}/Contents/PlugIns"
WIDGET_APPEX="${PLUGINS_DIR}/LoomWidgetExtension.appex"
WIDGET_BIN="${WIDGET_APPEX}/Contents/MacOS/LoomWidgetExtension"
WIDGET_PLIST="${WIDGET_APPEX}/Contents/Info.plist"
APP_PLIST="${APP_BUNDLE}/Contents/Info.plist"

echo "=================================================="
echo "Starting Loom Widget Package Verification"
echo "=================================================="

# Ensure app is packaged
if [[ ! -d "${WIDGET_APPEX}" ]]; then
    if [[ $# -gt 0 ]]; then
        echo "FAIL: Widget extension missing from specified app: ${APP_BUNDLE}" >&2
        exit 1
    fi
    echo "==> Loom.app or widget extension not found. Running build-app.sh..."
    bash "${ROOT_DIR}/scripts/build-app.sh"
fi

echo "Check 1: Verifying widget extension bundle existence..."
if [[ ! -d "${WIDGET_APPEX}" ]]; then
    echo "FAIL: Widget extension bundle missing at ${WIDGET_APPEX}" >&2
    exit 1
fi
echo "  PASS: Found ${WIDGET_APPEX}"

echo "Check 2: Verifying widget executable binary..."
if [[ ! -x "${WIDGET_BIN}" ]]; then
    echo "FAIL: Widget executable missing or not executable at ${WIDGET_BIN}" >&2
    exit 1
fi
bin_type="$(file -b "${WIDGET_BIN}")"
if [[ "${bin_type}" != *"Mach-O 64-bit"* ]]; then
    echo "FAIL: Unexpected binary format: ${bin_type}" >&2
    exit 1
fi
echo "  PASS: Widget binary is valid Mach-O executable (${bin_type})"

echo "Check 3: Verifying bundle identifiers and extension point..."
app_id="$(defaults read "${APP_PLIST}" CFBundleIdentifier 2>/dev/null || plutil -extract CFBundleIdentifier raw "${APP_PLIST}")"
widget_id="$(defaults read "${WIDGET_PLIST}" CFBundleIdentifier 2>/dev/null || plutil -extract CFBundleIdentifier raw "${WIDGET_PLIST}")"
ext_point="$(defaults read "${WIDGET_PLIST}" NSExtension.NSExtensionPointIdentifier 2>/dev/null || plutil -extract NSExtension.NSExtensionPointIdentifier raw "${WIDGET_PLIST}")"

if [[ "${app_id}" != "com.chaiwithcode.loom" ]]; then
    echo "FAIL: Main app bundle ID mismatch (got: ${app_id}, expected: com.chaiwithcode.loom)" >&2
    exit 1
fi

if [[ "${widget_id}" != "com.chaiwithcode.loom.widget" ]]; then
    echo "FAIL: Widget extension bundle ID mismatch (got: ${widget_id}, expected: com.chaiwithcode.loom.widget)" >&2
    exit 1
fi

if [[ "${ext_point}" != "com.apple.widgetkit-extension" ]]; then
    echo "FAIL: Extension point mismatch (got: ${ext_point}, expected: com.apple.widgetkit-extension)" >&2
    exit 1
fi
echo "  PASS: Main app ID (${app_id}) and widget extension ID (${widget_id}) verified"
echo "  PASS: Extension point is ${ext_point}"

echo "Check 4: Verifying App Group entitlements..."
app_entitlements="$(codesign -d --entitlements :- "${APP_BUNDLE}" 2>/dev/null || true)"
widget_entitlements="$(codesign -d --entitlements :- "${WIDGET_APPEX}" 2>/dev/null || true)"

if [[ "${app_entitlements}" != *"group.com.chaiwithcode.loom"* ]]; then
    echo "FAIL: Main app lacks group.com.chaiwithcode.loom entitlement" >&2
    exit 1
fi

if [[ "${widget_entitlements}" != *"group.com.chaiwithcode.loom"* ]]; then
    echo "FAIL: Widget extension lacks group.com.chaiwithcode.loom entitlement" >&2
    exit 1
fi

if [[ "${widget_entitlements}" != *"com.apple.security.app-sandbox"* ]]; then
    echo "FAIL: Widget extension lacks com.apple.security.app-sandbox entitlement" >&2
    exit 1
fi
echo "  PASS: Both main app and widget extension contain group.com.chaiwithcode.loom"
echo "  PASS: Widget extension is sandboxed (com.apple.security.app-sandbox = true)"

echo "Check 5: Verifying recursive code signature integrity..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
echo "  PASS: Recursive code signature is valid and satisfies Designated Requirement"

echo "Check 6: Verifying 'loom://' URL scheme registration..."
if ! plutil -p "${APP_PLIST}" | grep -q '"loom"'; then
    echo "FAIL: CFBundleURLTypes does not contain 'loom' URL scheme in ${APP_PLIST}" >&2
    exit 1
fi
echo "  PASS: 'loom://' custom URL scheme is properly registered in CFBundleURLTypes"

echo "Check 7: Verifying all widget symbols and identifiers in extension binary..."
for symbol in LoomSmallWidgetView LoomMediumWidgetView LoomQuotaWidgetView LoomUsageOverviewMediumView LoomUsageOverviewLargeView; do
    if ! nm -gU "${WIDGET_BIN}" 2>/dev/null | grep -q "${symbol}" && ! strings "${WIDGET_BIN}" | grep -q "${symbol}"; then
        echo "FAIL: Widget symbol ${symbol} missing in ${WIDGET_BIN}" >&2
        exit 1
    fi
done
for kind in "com.chaiwithcode.loom.widget" "com.chaiwithcode.loom.quotas" "com.chaiwithcode.loom.usage-overview"; do
    if ! strings "${WIDGET_BIN}" | grep -q "${kind}"; then
        echo "FAIL: Widget kind '${kind}' missing in ${WIDGET_BIN}" >&2
        exit 1
    fi
done
echo "  PASS: All 3 widgets (Sessions, Quotas, Usage Overview) verified in widget binary"

echo "=================================================="
echo "ALL WIDGET PACKAGE CHECKS PASSED SUCCESSFULLY"
echo "=================================================="
