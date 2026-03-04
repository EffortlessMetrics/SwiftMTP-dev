#!/usr/bin/env bash
set -euo pipefail

echo "🚀 SwiftMTP Development Setup"
echo "=============================="

# Check prerequisites
echo "📋 Checking prerequisites..."

# Xcode
if ! xcode-select -p &>/dev/null; then
  echo "❌ Xcode not found. Install from App Store."
  exit 1
fi
echo "  ✅ Xcode: $(xcodebuild -version | head -1)"

# Swift
echo "  ✅ Swift: $(swift --version 2>&1 | head -1)"

# libusb
if ! brew list libusb &>/dev/null; then
  echo "📦 Installing libusb..."
  brew install libusb
fi
echo "  ✅ libusb: $(brew info libusb --json | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["versions"]["stable"])')"

# Build XCFramework if needed
if [ ! -d "SwiftMTPKit/.build" ] || [ ! -f "ThirdParty/libusb.xcframework/Info.plist" ]; then
  echo "🔨 Building libusb XCFramework..."
  if [ -f "scripts/build-libusb-xcframework.sh" ]; then
    bash scripts/build-libusb-xcframework.sh
  else
    echo "  ⚠️  XCFramework build script not found. Using system libusb."
  fi
fi

# Initial build
echo "🔨 Building SwiftMTP..."
cd SwiftMTPKit
swift build 2>&1 | tail -3

# Quick smoke test
echo "🧪 Running smoke test..."
swift test --filter CoreTests 2>&1 | tail -3

echo ""
echo "✅ Setup complete! Quick start:"
echo "  cd SwiftMTPKit"
echo "  swift run swiftmtp --help"
echo ""
echo "Mock device testing:"
echo "  export SWIFTMTP_DEMO_MODE=1"
echo "  export SWIFTMTP_MOCK_PROFILE=pixel7  # options: pixel7, galaxy, iphone, canon"
echo "  swift run swiftmtp probe"
