#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/MacAquariumWallpaper.app"
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [ ! -d "$sdk" ]; then sdk="$(xcrun --sdk macosx --show-sdk-path)"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -O -swift-version 5 -sdk "$sdk" \
  -target "$(uname -m)-apple-macosx14.0" Sources/*.swift \
  -o "$app/Contents/MacOS/MacAquariumWallpaper"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Ocean.metal "$app/Contents/Resources/Ocean.metal"
cp Resources/PondEnvironment.png "$app/Contents/Resources/PondEnvironment.png"
codesign --force --sign - "$app"
echo "Built: $app"
