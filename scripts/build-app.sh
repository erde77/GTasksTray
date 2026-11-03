#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
# SwiftPM can otherwise record the deployment target as the SDK version.
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
min_version="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' scripts/Info.plist)"
build_args=(--configuration release -Xlinker -platform_version -Xlinker macos -Xlinker "$min_version" -Xlinker "$sdk_version")
swift build "${build_args[@]}" "$@"
bin_path="$(swift build "${build_args[@]}" --show-bin-path "$@")"
app="$PWD/dist/GTasksTray.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$bin_path/GTasksTray" "$app/Contents/MacOS/GTasksTray"
install -m 644 scripts/Info.plist "$app/Contents/Info.plist"
install -m 644 Resources/TaskComplete.wav "$app/Contents/Resources/TaskComplete.wav"
codesign --force --sign - "$app"
printf '\nGotowe: %s\n' "$app"
