#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [ ! -d "$sdk" ]; then sdk="$(xcrun --sdk macosx --show-sdk-path)"; fi
reference_dir=$(mktemp -d "${TMPDIR:-/tmp}/pond-canvas-reference.XXXXXX")
trap 'rm -rf "$reference_dir"' EXIT
git show 32c1c66:Sources/FishDrawingWindow.swift > "$reference_dir/FishDrawingWindow.swift"
xcrun swiftc -O -swift-version 5 -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" Sources/OceanTypes.swift Sources/PondGeometry.swift Sources/OceanSimulation.swift Sources/FishMesh.swift Sources/FishDrawing.swift "$reference_dir/FishDrawingWindow.swift" Tests/CanvasCacheTests.swift -o "$reference_dir/reference-tests"
"$reference_dir/reference-tests" --record-reference
xcrun swiftc -O -swift-version 5 -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" Sources/OceanTypes.swift Sources/PondGeometry.swift Sources/OceanSimulation.swift Sources/FishMesh.swift Sources/FishDrawing.swift Sources/FishDrawingWindow.swift Tests/CanvasCacheTests.swift -D CACHE_METRICS -o build/tests/canvas-cache-tests
build/tests/canvas-cache-tests "$@"
