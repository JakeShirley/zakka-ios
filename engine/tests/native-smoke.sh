#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p engine/.build
sources=(App/Rendering/Artwork{Engine,Media,Raster}.swift engine/tests/RasterSmoke.swift)
bundle="$PWD/App/Rendering/ZakkaArtwork.bundle"
if [[ "${1:-}" = simulator ]]; then
  # Standalone helper only; does not launch/build the app or change any server state.
  arch="$(uname -m)"
  xcrun --sdk iphonesimulator swiftc -swift-version 6 -parse-as-library \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -target "$arch-apple-ios27.0-simulator" "${sources[@]}" -o engine/.build/raster-sim
  xcrun simctl spawn "${SIMULATOR_UDID:-booted}" "$PWD/engine/.build/raster-sim" "$bundle"
else
  xcrun swiftc -swift-version 6 -parse-as-library "${sources[@]}" -o engine/.build/raster-smoke
  engine/.build/raster-smoke "$bundle"
fi
