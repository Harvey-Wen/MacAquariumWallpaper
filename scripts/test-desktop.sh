#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [ ! -d "$sdk" ]; then sdk="$(xcrun --sdk macosx --show-sdk-path)"; fi
xcrun swiftc -O -swift-version 5 -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" \
  Sources/OceanTypes.swift Sources/OceanSimulation.swift Sources/FishMesh.swift Sources/OceanRenderer.swift \
  Sources/DesktopInput.swift Sources/DesktopController.swift Tests/DesktopTests.swift -o build/tests/desktop-tests
build/tests/desktop-tests
