#!/usr/bin/env bash
set -euo pipefail
# Generate SwiftMTP DocC documentation
# Usage: ./scripts/generate-docs.sh [--open]

OPEN=false
for arg in "$@"; do
  [[ "$arg" == "--open" ]] && OPEN=true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_PATH="$REPO_ROOT/Docs/SwiftMTP.doccarchive"

cd "$REPO_ROOT/SwiftMTPKit"

if ! swift package plugin --list 2>/dev/null | grep -q "generate-documentation" && \
   ! swift package --help 2>/dev/null | grep -q "generate-documentation"; then
  # Check if the subcommand exists at all
  if ! swift package generate-documentation --help &>/dev/null; then
    echo "Warning: 'swift package generate-documentation' is unavailable (requires Xcode 14+ / Swift-DocC plugin)."
    echo "Install Xcode 14 or later, or add the Swift-DocC plugin to Package.swift."
    exit 0
  fi
fi

echo "Generating DocC documentation for SwiftMTPCore..."
swift package generate-documentation \
  --target SwiftMTPCore \
  --output-path "$OUTPUT_PATH" 2>&1

echo "Documentation generated: $OUTPUT_PATH"

if $OPEN; then
  open "$OUTPUT_PATH"
fi
