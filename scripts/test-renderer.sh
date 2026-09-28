#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
task_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [[ ! -d "$task_sdk" ]]; then task_sdk=$(xcrun --show-sdk-path); fi
swiftc -sdk "$task_sdk" -target arm64-apple-macosx14.0 -O \
  Sources/OceanTypes.swift Sources/PondGeometry.swift Sources/OceanSimulation.swift Sources/FishMesh.swift Sources/FishDrawing.swift Sources/OceanRenderer.swift Tests/RenderTests.swift \
  -framework AppKit -framework Metal -framework MetalKit -framework QuartzCore -o .build/render-tests
.build/render-tests "$@"
