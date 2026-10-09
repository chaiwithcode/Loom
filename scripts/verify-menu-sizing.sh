#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d /private/tmp/loom-menu-probe.XXXXXX)
trap 'rm -rf "$probe_dir"' EXIT
swift build --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "$probe_dir/cache"
objects=(.build/debug/LoomCore.build/*.swift.o)
for object in .build/debug/Loom.build/*.swift.o; do
    [[ "$object" == */LoomApp.swift.o ]] || objects+=("$object")
done
swiftc -parse-as-library -module-cache-path "$probe_dir/cache" \
    -I .build/debug/Modules Tests/MenuSizingProbe.swift "${objects[@]}" \
    -o "$probe_dir/probe"
"$probe_dir/probe"
