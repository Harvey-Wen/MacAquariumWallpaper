#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/fish-drawing.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT INT TERM
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [ ! -d "$sdk_path" ]; then sdk_path=$(xcrun --show-sdk-path); fi

swiftc -sdk "$sdk_path" -target arm64-apple-macosx14.0 \
    "$project_dir/Sources/OceanTypes.swift" \
    "$project_dir/Sources/PondGeometry.swift" \
    "$project_dir/Sources/OceanSimulation.swift" \
    "$project_dir/Sources/FishMesh.swift" \
    "$project_dir/Sources/FishDrawing.swift" \
    "$project_dir/Tests/DrawingTests.swift" \
    -framework AppKit -o "$build_dir/DrawingTests"
"$build_dir/DrawingTests"
