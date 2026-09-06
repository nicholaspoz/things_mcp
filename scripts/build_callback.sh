#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bundle="$project_root/build/ThingsCallback.app"
mkdir -p "$bundle/Contents/MacOS" "$project_root/build/swift-module-cache"
cp "$project_root/native/Info.plist" "$bundle/Contents/Info.plist"
xcrun swiftc -module-cache-path "$project_root/build/swift-module-cache" \
    -framework AppKit -O "$project_root/native/ThingsCallback.swift" \
    -o "$bundle/Contents/MacOS/ThingsCallback"
"$bundle/Contents/MacOS/ThingsCallback" --self-test
printf '%s\n' "$bundle"
