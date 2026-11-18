#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p engine/.build/nativepkg
sources=(App/Rendering/Artwork{Engine,Media,Raster}.swift engine/tests/RasterSmoke.swift)
bundle="$PWD/App/Rendering/ZakkaArtwork.bundle"
# Link exactly the universal simulator slice distributed to app developers. No app build.
slice=Packages/ZakkaRaster/CResvg.xcframework/ios-arm64_x86_64-simulator
out=engine/.build/nativepkg
swift=(xcrun --sdk iphonesimulator swiftc -swift-version 6 -parse-as-library
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target "$(uname -m)-apple-ios27.0-simulator" -I "$slice/Headers")
"${swift[@]}" -module-name ZakkaRaster -emit-module -emit-module-path "$out/ZakkaRaster.swiftmodule" \
  -emit-object Packages/ZakkaRaster/Sources/ZakkaRaster/ResvgRasterizer.swift -o "$out/ZakkaRaster.o"
"${swift[@]}" -I "$out" "${sources[@]}" "$out/ZakkaRaster.o" "$slice/libresvg.a" -o "$out/raster-sim"
xcrun simctl spawn "${SIMULATOR_UDID:-booted}" "$PWD/$out/raster-sim" "$bundle" "$PWD/$out/photo-text.png" \
  "$PWD/engine/tests/fixtures/blue-marble.jpg"
