#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ocean-simulation.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT INT TERM
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [ ! -d "$sdk_path" ]; then
    sdk_path=$(xcrun --show-sdk-path)
fi

swiftc \
    -sdk "$sdk_path" \
    -target arm64-apple-macosx14.0 \
    "$project_dir/Sources/OceanTypes.swift" \
    "$project_dir/Sources/PondGeometry.swift" \
    "$project_dir/Sources/OceanSimulation.swift" \
    "$project_dir/Tests/SimulationTests.swift" \
    -o "$build_dir/SimulationTests"

"$build_dir/SimulationTests"
