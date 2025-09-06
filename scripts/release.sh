#!/usr/bin/env bash
set -euo pipefail

# Inputs
VER="${1:?Usage: scripts/release.sh vX.Y.Z}"
PKG="SwiftMTPKit"
PROD="swiftmtp"                    # Executable product name
OUT="dist/$VER"
MAC_ART="$OUT/$PROD-macos-arm64.tar.gz"
LIN_ART="$OUT/$PROD-linux-x86_64.tar.gz"   # optional, if you build on Linux too

echo "🔖 Tagging $VER"
git diff --quiet || { echo "❌ working tree dirty"; exit 1; }
git tag -a "$VER" -m "SwiftMTP $VER"
git push origin "$VER"

mkdir -p "$OUT"

echo "🧱 Building macOS (arm64, release)…"
swift build -c release --package-path "$PKG" --product "$PROD"
BIN="$(swift build -c release --package-path "$PKG" --product "$PROD" --show-bin-path)/$PROD"

echo "📦 Packaging $MAC_ART"
tar -C "$(dirname "$BIN")" -czf "$MAC_ART" "$PROD"
shasum -a 256 "$MAC_ART" > "$MAC_ART.sha256"

# (Optional) build Linux from a Linux runner and upload the second artifact
# echo "🧱 Building Linux …"
# [...]

echo "✅ Ready:"
ls -lh "$OUT"
