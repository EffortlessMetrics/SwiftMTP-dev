#!/usr/bin/env bash
set -euo pipefail
# Verify CHANGELOG.md has an entry for the current version.
# Usage: ./scripts/check-changelog.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

# 1. Try to find version from a "// Version: X.Y.Z" comment in SwiftMTPCore public sources
VERSION=""
if [[ -z "$VERSION" ]]; then
  VERSION=$(grep -r "// Version:" "$REPO_ROOT/SwiftMTPKit/Sources/SwiftMTPCore/Public/" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
fi

# 2. Fall back to latest git tag
if [[ -z "$VERSION" ]]; then
  VERSION=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
fi

if [[ -z "$VERSION" ]]; then
  # On shallow clones (CI), tags may not be available — check for [Unreleased] section instead
  if grep -qE "^## \[Unreleased\]" "$CHANGELOG"; then
    echo "OK: No version determined (shallow clone?), but CHANGELOG.md has [Unreleased] section."
    exit 0
  fi
  echo "Could not determine current version (no // Version: comment found and no git tags)."
  exit 1
fi

echo "Checking CHANGELOG.md for version $VERSION..."

if grep -qE "^## \[?${VERSION//./\\.}\]?" "$CHANGELOG"; then
  echo "OK: CHANGELOG.md contains an entry for $VERSION."
  exit 0
else
  echo "ERROR: CHANGELOG.md is missing an entry for version $VERSION."
  echo "Add a '## [$VERSION]' or '## $VERSION' section to CHANGELOG.md before releasing."
  exit 1
fi
