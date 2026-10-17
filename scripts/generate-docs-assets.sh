#!/usr/bin/env bash
#
#  generate-docs-assets.sh
#  Loom
#
#  Copyright © 2026 Deepak Sharma (ChaiWithCode).
#  Licensed under the MIT License. See LICENSE for details.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TMP_DIR="/tmp/loom-docs-capture"
mkdir -p "${TMP_DIR}"

TMP_WIDGET_SRC="${TMP_DIR}/LoomWidgetForDocs.swift"
{
    echo "import LoomCore"
    echo "import Loom"
    sed -e 's/@main/\/\/ @main/g' "${ROOT_DIR}/LoomWidget/LoomWidget.swift"
} > "${TMP_WIDGET_SRC}"

echo "==> Gathering compiled objects..."
objects=(.build/debug/LoomCore.build/*.swift.o)
for object in .build/debug/Loom.build/*.swift.o; do
    [[ "$object" == */LoomApp.swift.o ]] || objects+=("$object")
done

echo "==> Compiling capture runner..."
RUNNER_BIN="${TMP_DIR}/capture-runner"

swiftc -parse-as-library \
    -target arm64-apple-macos14.0 \
    -module-cache-path "${TMPDIR:-/tmp}/loom-module-cache" \
    -I .build/debug/Modules \
    -F .build/debug \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker .build/debug \
    -framework SwiftUI -framework WidgetKit -framework Foundation -framework AppKit -framework Vision -framework CoreGraphics \
    "${objects[@]}" \
    "${TMP_WIDGET_SRC}" \
    "${ROOT_DIR}/scripts/capture-docs-assets.swift" \
    -o "${RUNNER_BIN}"

echo "==> Running asset capture..."
"${RUNNER_BIN}"

echo "==> Asset capture complete!"
