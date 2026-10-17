#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

OUTPUT_DIR="/tmp/loom-widget-qa/screenshots"
mkdir -p "${OUTPUT_DIR}"
rm -rf "${OUTPUT_DIR}"/*

TMP_WIDGET_SRC="/tmp/LoomWidgetForQA.swift"
# Comment out @main and ensure LoomCore is imported
{
    echo "import LoomCore"
    echo "import Loom"
    sed -e 's/@main/\/\/ @main/g' "${ROOT_DIR}/LoomWidget/LoomWidget.swift"
} > "${TMP_WIDGET_SRC}"

echo "==> Building debug objects if needed..."
if [[ ! -d ".build/debug/Modules" ]]; then
    swift build --disable-sandbox
fi

objects=(.build/debug/LoomCore.build/*.swift.o)
for object in .build/debug/Loom.build/*.swift.o; do
    [[ "$object" == */LoomApp.swift.o ]] || objects+=("$object")
done

echo "==> Building WidgetVisualProbe..."
PROBE_BIN="/tmp/loom-widget-qa/WidgetVisualProbe"

swiftc -parse-as-library \
    -target arm64-apple-macos14.0 \
    -module-cache-path "${TMPDIR:-/tmp}/loom-module-cache" \
    -I .build/debug/Modules \
    -F .build/debug \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker .build/debug \
    -framework SwiftUI -framework WidgetKit -framework Foundation -framework AppKit -framework Vision \
    "${objects[@]}" \
    "${TMP_WIDGET_SRC}" \
    "${ROOT_DIR}/Tests/WidgetVisualProbe.swift" \
    -o "${PROBE_BIN}"

echo "==> Running WidgetVisualProbe..."
"${PROBE_BIN}"

echo "==> Visual inspection captures complete at ${OUTPUT_DIR}"
