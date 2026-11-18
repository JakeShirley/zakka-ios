#!/bin/bash
# Rebuild the static iOS device + universal simulator resvg C API. Requires Xcode and rustup.
set -euo pipefail
cd "$(dirname "$0")"
pkg="$PWD"
work="$pkg/../../engine/.build/resvg-src"
version=0.45.1
rust=1.91.1
mkdir -p "$work"
cd "$work"
work="$PWD"
if [[ ! -f resvg.tar.gz ]]; then
  curl -fsSL --retry 3 "https://codeload.github.com/linebender/resvg/tar.gz/refs/tags/v$version" -o resvg.tar.gz
fi
echo '02915519b7409f43110f3cbdc5f87724efd58da1d8516914bdabf060c8a9a178  resvg.tar.gz' | shasum -c -a 256
tar -xzf resvg.tar.gz
cd "resvg-$version"
patch -s -p1 < "$pkg/data-only.patch"
rustup toolchain install "$rust" --profile minimal
targets=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
features=text,raster-images,system-fonts
rustup target add --toolchain "$rust" "${targets[@]}"
export IPHONEOS_DEPLOYMENT_TARGET=27.0 ZERO_AR_DATE=1
export CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_OPT_LEVEL=s CARGO_PROFILE_RELEASE_PANIC=abort
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 CARGO_PROFILE_RELEASE_STRIP=debuginfo
export CARGO_TARGET_DIR="$work/target"
export RUSTFLAGS="--remap-path-prefix=$PWD=/resvg --remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo"
mkdir -p "$work"/{headers,device,sim}
for target in "${targets[@]}"; do
  cargo "+$rust" rustc --locked --release --target "$target" -p resvg-capi \
    --no-default-features --features "$features" --crate-type staticlib
done
lib() { printf '%s/%s/release/libresvg.a' "$CARGO_TARGET_DIR" "$1"; }
cp "$(lib aarch64-apple-ios)" "$work/device/libresvg.a"
xcrun lipo -create "$(lib aarch64-apple-ios-sim)" "$(lib x86_64-apple-ios)" -output "$work/sim/libresvg.a"
# Keep externally linkable C symbols/relocations, discard local symbols in all slices.
xcrun strip -S -x "$work/device/libresvg.a" "$work/sim/libresvg.a"
cp crates/c-api/resvg.h "$work/headers/"
printf 'module CResvg { header "resvg.h" export * }\n' > "$work/headers/module.modulemap"
rm -rf "$work/CResvg.xcframework"
xcodebuild -create-xcframework \
  -library "$work/device/libresvg.a" -headers "$work/headers" \
  -library "$work/sim/libresvg.a" -headers "$work/headers" -output "$work/CResvg.xcframework"
mkdir -p "$pkg/CResvg.xcframework"
rsync -ac --delete "$work/CResvg.xcframework/" "$pkg/CResvg.xcframework/"
node "$pkg/notices.mjs" "$rust" "$features" "$pkg/../../App/Rendering/ZakkaArtwork.bundle"
