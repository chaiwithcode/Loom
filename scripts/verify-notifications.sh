#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

probe_dir=$(mktemp -d /private/tmp/loom-notification-probe.XXXXXX)
probe_pid=""

cleanup() {
    if [[ -n "$probe_pid" ]] && kill -0 "$probe_pid" 2>/dev/null; then
        kill -TERM "$probe_pid" 2>/dev/null || true
    fi
    rm -rf "$probe_dir"
}
trap cleanup EXIT INT TERM

echo "==> Building Loom targets for Notification probe..."
swift build --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "$probe_dir/cache"

objects=(.build/debug/LoomCore.build/*.swift.o)
for object in .build/debug/Loom.build/*.swift.o; do
    [[ "$object" == */LoomApp.swift.o ]] || objects+=("$object")
done

echo "==> Linking NotificationProbe..."
swiftc -parse-as-library -module-cache-path "$probe_dir/cache" \
    -I .build/debug/Modules -F .build/debug -framework Sparkle \
    -Xlinker -rpath -Xlinker .build/debug \
    Tests/NotificationProbe.swift "${objects[@]}" \
    -o "$probe_dir/probe"

echo "==> Executing NotificationProbe..."
"$probe_dir/probe" &
probe_pid=$!
wait "$probe_pid"
probe_status=$?
probe_pid=""
echo "==> NotificationProbe finished with exit code $probe_status"

exit "$probe_status"
