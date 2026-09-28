#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [ ! -d "$sdk" ]; then sdk="$(xcrun --sdk macosx --show-sdk-path)"; fi
renderer=Sources/OceanRenderer.swift
flags=(-D BASELINE)
if [ "${1:-}" = "--baseline" ]; then
  reference_dir=$(mktemp -d "${TMPDIR:-/tmp}/pond-display-reference.XXXXXX")
  trap 'rm -rf "$reference_dir"' EXIT
  git show 32c1c66:Sources/OceanRenderer.swift > "$reference_dir/OceanRenderer.swift"
  renderer="$reference_dir/OceanRenderer.swift"
else
  flags=(-D METRICS)
fi
xcrun swiftc -O -swift-version 5 -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" "${flags[@]}" Sources/PerformanceMetrics.swift Sources/OceanTypes.swift Sources/PondGeometry.swift Sources/OceanSimulation.swift Sources/FishMesh.swift Sources/FishDrawing.swift "$renderer" Tests/DisplayPerformanceTests.swift -o build/tests/display-performance-tests
build/tests/display-performance-tests
