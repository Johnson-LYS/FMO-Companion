#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
output="$repository_root/FMOc/Vendor/Opus.xcframework"
bridge_root="$repository_root/scripts/opus-bridge"
temporary_root=$(mktemp -d /tmp/fmoc-opus-build.XXXXXX)
trap 'rm -rf "$temporary_root"' EXIT

git clone --branch v1.6.1 --depth 1 https://github.com/xiph/opus.git "$temporary_root/opus"

configure_and_install() {
    local platform=$1
    local sysroot=$2
    local architectures=$3
    local build_root="$temporary_root/build-$platform"
    local install_root="$temporary_root/install-$platform"
    cmake -S "$temporary_root/opus" -B "$build_root" -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_OSX_ARCHITECTURES="$architectures" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
        -DCMAKE_INSTALL_PREFIX="$install_root" \
        -DOPUS_BUILD_PROGRAMS=OFF \
        -DOPUS_BUILD_TESTING=OFF \
        -DOPUS_INSTALL_PKG_CONFIG_MODULE=OFF
    cmake --build "$build_root" --config Release
    cmake --install "$build_root" --config Release
}

configure_and_install device iphoneos arm64
configure_and_install simulator iphonesimulator 'arm64;x86_64'

developer_dir=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
device_sdk="$developer_dir/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
simulator_sdk="$developer_dir/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
device_install="$temporary_root/install-device"
simulator_install="$temporary_root/install-simulator"

clang -arch arm64 -isysroot "$device_sdk" -miphoneos-version-min=26.0 \
    -I "$device_install/include/opus" -c "$bridge_root/OpusBridge.c" \
    -o "$temporary_root/bridge-device.o"
libtool -static "$device_install/lib/libopus.a" "$temporary_root/bridge-device.o" \
    -o "$temporary_root/libopus-device.a"

for architecture in arm64 x86_64; do
    lipo "$simulator_install/lib/libopus.a" -thin "$architecture" \
        -output "$temporary_root/libopus-simulator-$architecture.a"
    clang -arch "$architecture" -isysroot "$simulator_sdk" -mios-simulator-version-min=26.0 \
        -I "$simulator_install/include/opus" -c "$bridge_root/OpusBridge.c" \
        -o "$temporary_root/bridge-simulator-$architecture.o"
    libtool -static "$temporary_root/libopus-simulator-$architecture.a" \
        "$temporary_root/bridge-simulator-$architecture.o" \
        -o "$temporary_root/libopus-simulator-$architecture-bridged.a"
done
lipo -create "$temporary_root/libopus-simulator-arm64-bridged.a" \
    "$temporary_root/libopus-simulator-x86_64-bridged.a" \
    -output "$temporary_root/libopus-simulator.a"

xcodebuild -create-xcframework \
    -library "$temporary_root/libopus-device.a" -headers "$device_install/include/opus" \
    -library "$temporary_root/libopus-simulator.a" -headers "$simulator_install/include/opus" \
    -output "$temporary_root/Opus.xcframework"

for headers in "$temporary_root/Opus.xcframework"/*/Headers; do
    cp "$bridge_root/OpusBridge.h" "$headers/OpusBridge.h"
    cp "$repository_root/scripts/opus.module.modulemap" "$headers/module.modulemap"
done

if [[ -e "$output" ]]; then
    mv "$output" "$temporary_root/Opus.previous.xcframework"
fi
mv "$temporary_root/Opus.xcframework" "$output"
shasum -a 256 "$output"/*/libopus.a
