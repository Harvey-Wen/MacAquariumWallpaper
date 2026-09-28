#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
task_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [ ! -d "$task_sdk" ]; then task_sdk="$(xcrun --show-sdk-path)"; fi
swiftc -O -swift-version 5 -sdk "$task_sdk" -target "$(uname -m)-apple-macosx14.0" \
  Sources/PerformanceMetrics.swift Sources/OceanTypes.swift Sources/PondGeometry.swift Sources/OceanSimulation.swift Sources/FishMesh.swift \
  Sources/FishDrawing.swift Sources/OceanRenderer.swift Sources/DesktopInput.swift Sources/DesktopBackdrop.swift \
  Sources/DesktopController.swift Tests/CustomFishDesktopTests.swift -o .build/custom-fish-desktop-tests
.build/custom-fish-desktop-tests
