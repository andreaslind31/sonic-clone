#!/bin/sh
# Export release builds for every preset. Set GODOT to point at a specific binary.
#
#   GODOT=~/Applications/Godot.app/Contents/MacOS/Godot ./tools/build.sh
#
# Export templates matching the editor version must be installed; the editor
# fetches them under Editor > Manage Export Templates.
set -e
GODOT="${GODOT:-godot}"

for dir in build/macos build/linux build/windows; do
    mkdir -p "$dir"
done

for preset in "macOS" "Linux" "Windows Desktop"; do
    printf 'exporting %s... ' "$preset"
    "$GODOT" --headless --export-release "$preset" >/dev/null 2>&1
    echo done
done

echo
du -sh build/*/* 2>/dev/null | grep -v '\.pck$' || true
