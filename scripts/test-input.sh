#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [ ! -d "$sdk" ]; then sdk="$(xcrun --sdk macosx --show-sdk-path)"; fi
xcrun swiftc -swift-version 5 -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" Sources/DesktopInput.swift Tests/InputTests.swift -o build/tests/input-tests
build/tests/input-tests
