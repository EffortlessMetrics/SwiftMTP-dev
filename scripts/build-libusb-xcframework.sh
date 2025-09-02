#!/usr/bin/env bash
set -euo pipefail

LIBUSB_VERSION=${LIBUSB_VERSION:-1.0.27}
BUILD_DIR="$(pwd)/ThirdParty/build"
HEADERS_DIR="$(pwd)/ThirdParty/libusb-headers"
XC_OUT="$(pwd)/ThirdParty/CLibusb.xcframework"

rm -rf "$BUILD_DIR" "$XC_OUT" "$HEADERS_DIR"
mkdir -p "$BUILD_DIR" "$HEADERS_DIR"

# Download and extract libusb
curl -L "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2" -o /tmp/libusb-${LIBUSB_VERSION}.tar.bz2
tar -xf /tmp/libusb-${LIBUSB_VERSION}.tar.bz2 -C /tmp

# Copy headers
cp -R "/tmp/libusb-${LIBUSB_VERSION}/libusb" "$HEADERS_DIR/"

# Create modulemap for SPM
cat > "$HEADERS_DIR/module.modulemap" <<'MAP'
module CLibusb [system] {
  header "libusb.h"
  export *
}
MAP

# Build for arm64
pushd "/tmp/libusb-${LIBUSB_VERSION}/Xcode" >/dev/null
xcodebuild -project libusb.xcodeproj \
  -scheme libusb \
  -configuration Release \
  -sdk macosx \
  -arch arm64 \
  -derivedDataPath "$BUILD_DIR/arm64" \
  build

# Build for x86_64
xcodebuild -project libusb.xcodeproj \
  -scheme libusb \
  -configuration Release \
  -sdk macosx \
  -arch x86_64 \
  -derivedDataPath "$BUILD_DIR/x86_64" \
  build
popd >/dev/null

# Find the built libraries
ARM64_LIB=$(find "$BUILD_DIR/arm64" -name "libusb*.dylib" | head -1)
X86_64_LIB=$(find "$BUILD_DIR/x86_64" -name "libusb*.dylib" | head -1)

if [ -z "$ARM64_LIB" ] || [ -z "$X86_64_LIB" ]; then
  echo "Error: Could not find built libraries"
  echo "ARM64: $ARM64_LIB"
  echo "X86_64: $X86_64_LIB"
  exit 1
fi

# Create separate header directories for each architecture
HEADERS_ARM64_DIR="$HEADERS_DIR-arm64"
HEADERS_X86_64_DIR="$HEADERS_DIR-x86_64"
cp -R "$HEADERS_DIR" "$HEADERS_ARM64_DIR"
cp -R "$HEADERS_DIR" "$HEADERS_X86_64_DIR"

# Create XCFramework
xcodebuild -create-xcframework \
  -library "$ARM64_LIB" -headers "$HEADERS_ARM64_DIR" \
  -library "$X86_64_LIB" -headers "$HEADERS_X86_64_DIR" \
  -output "$XC_OUT"

# Clean up temporary header directories
rm -rf "$HEADERS_ARM64_DIR" "$HEADERS_X86_64_DIR"

echo "XCFramework created at: $XC_OUT"
codesign --force --sign - "$XC_OUT"
