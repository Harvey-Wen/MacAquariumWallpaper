#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/fish-drawing-window.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT INT TERM
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [ ! -d "$sdk_path" ]; then sdk_path=$(xcrun --show-sdk-path); fi

if [ "${1:-}" = "--fixture" ]; then
    test_source="$project_dir/Tests/DrawingEditorFixture.swift"
    app_dir="$project_dir/.build/DrawingEditorFixture.app"
    mkdir -p "$app_dir/Contents/MacOS"
    executable="$app_dir/Contents/MacOS/DrawingEditorFixture"
    cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.macaquariumwallpaper.drawing-fixture</string>
<key>CFBundleExecutable</key><string>DrawingEditorFixture</string>
<key>CFBundleName</key><string>Drawing Editor Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
else
    test_source="$project_dir/Tests/DrawingWindowTests.swift"
    executable="$build_dir/DrawingWindowTests"
fi

swiftc -swift-version 5 -sdk "$sdk_path" -target arm64-apple-macosx14.0 \
    "$project_dir/Sources/OceanTypes.swift" \
    "$project_dir/Sources/PondGeometry.swift" \
    "$project_dir/Sources/OceanSimulation.swift" \
    "$project_dir/Sources/FishMesh.swift" \
    "$project_dir/Sources/FishDrawing.swift" \
    "$project_dir/Sources/FishDrawingWindow.swift" \
    "$test_source" \
    -framework AppKit -o "$executable"
if [ "${1:-}" = "--fixture" ]; then
    echo "$app_dir"
else
    "$executable"
fi
