#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p /tmp/loom-settings-verification
log_file="/tmp/loom-settings-verification/settings-probe.log"
exec > >(tee "$log_file") 2>&1

probe_dir=$(mktemp -d /private/tmp/loom-settings-probe.XXXXXX)
probe_pid=""

cleanup() {
    if [[ -n "$probe_pid" ]] && kill -0 "$probe_pid" 2>/dev/null; then
        kill -TERM "$probe_pid" 2>/dev/null || true
    fi
    rm -rf "$probe_dir"
}
trap cleanup EXIT INT TERM

echo "==> Building Loom targets for Settings probe..."
swift build --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "$probe_dir/cache"

objects=(.build/debug/LoomCore.build/*.swift.o)
for object in .build/debug/Loom.build/*.swift.o; do
    [[ "$object" == */LoomApp.swift.o ]] || objects+=("$object")
done

echo "==> Linking SettingsProbe..."
swiftc -parse-as-library -module-cache-path "$probe_dir/cache" \
    -I .build/debug/Modules -F .build/debug -framework Sparkle \
    -Xlinker -rpath -Xlinker .build/debug \
    Tests/SettingsProbe.swift "${objects[@]}" \
    -o "$probe_dir/probe"

echo "==> Executing SettingsProbe..."
"$probe_dir/probe" &
probe_pid=$!
wait "$probe_pid"
probe_status=$?
probe_pid=""
echo "==> SettingsProbe finished with exit code $probe_status"

exec 1>&- 2>&-
exit "$probe_status"
