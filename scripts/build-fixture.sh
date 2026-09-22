#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/DesktopFixture.app"
mkdir -p "$app/Contents/MacOS"
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [ ! -d "$sdk" ]; then sdk="$(xcrun --sdk macosx --show-sdk-path)"; fi
xcrun swiftc -parse-as-library -swift-version 5 -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" \
    Tests/DesktopFixture.swift -o "$app/Contents/MacOS/DesktopFixture"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DesktopFixture</string>
<key>CFBundleIdentifier</key><string>local.macaquariumwallpaper.fixture</string>
<key>CFBundleName</key><string>海洋桌面验证</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
