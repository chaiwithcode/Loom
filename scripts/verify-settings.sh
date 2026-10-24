#!/usr/bin/env bash
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

echo "==> Preparing SettingsProbe.app bundle wrapper..."
mkdir -p "$probe_dir/SettingsProbe.app/Contents/MacOS"
mkdir -p "$probe_dir/SettingsProbe.app/Contents/Resources"
cat << 'EOF' > "$probe_dir/SettingsProbe.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.loom.SettingsProbe</string>
    <key>CFBundleName</key>
    <string>SettingsProbe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
</dict>
</plist>
EOF

echo "==> Linking SettingsProbe..."
swiftc -parse-as-library -module-cache-path "$probe_dir/cache" \
    -I .build/debug/Modules -F .build/debug -framework Sparkle \
    -Xlinker -rpath -Xlinker .build/debug \
    Tests/SettingsProbe.swift "${objects[@]}" \
    -o "$probe_dir/SettingsProbe.app/Contents/MacOS/SettingsProbe"

echo "==> Executing SettingsProbe..."
probe_output="$probe_dir/probe.log"
"$probe_dir/SettingsProbe.app/Contents/MacOS/SettingsProbe" > "$probe_output" 2>&1 &
probe_pid=$!
probe_status=0
wait "$probe_pid" || probe_status=$?
probe_pid=""
cat "$probe_output"
echo "==> SettingsProbe finished with exit code $probe_status"

if [[ "$probe_status" -eq 0 ]] && ! grep -Fxq 'ALL PROBE CHECKS PASSED SUCCESSFULLY' "$probe_output"; then
    echo "ERROR: SettingsProbe exited without completing every check."
    probe_status=1
fi

exit "$probe_status"
