#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.
#
# Pre-PR gate — runs all quality checks before opening a pull request.
# Usage: ./scripts/pre-pr.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

pass=0
fail=0

step() {
  echo ""
  echo "▸ $1"
}

ok() {
  echo "  ✅ $1"
  pass=$((pass + 1))
}

die() {
  echo "  ❌ $1"
  fail=$((fail + 1))
}

echo "🔍 SwiftMTP Pre-PR Gate"
echo "========================"

# ── Step 1: swift-format lint ────────────────────────────────────────
step "Checking code formatting…"
if swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests --strict 2>&1 | head -20; then
  ok "Formatting OK"
else
  die "Formatting issues found. Run: swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests"
fi

# ── Step 2: Build ────────────────────────────────────────────────────
step "Building (swift build)…"
if (cd SwiftMTPKit && swift build 2>&1 | tail -5); then
  ok "Build OK"
else
  die "Build failed"
fi

# ── Step 3: Core tests ──────────────────────────────────────────────
step "Running CoreTests…"
if (cd SwiftMTPKit && swift test --filter CoreTests 2>&1 | tail -5); then
  ok "CoreTests passed"
else
  die "CoreTests failed"
fi

# ── Step 4: Quirks validation ────────────────────────────────────────
step "Validating quirks…"
if bash scripts/validate-quirks.sh 2>&1 | tail -5; then
  ok "Quirks valid"
else
  die "Quirks validation failed"
fi

# ── Step 5: No large binary diffs ───────────────────────────────────
step "Checking for large file changes (>1 MB)…"
large_files=$(git diff --cached --name-only --diff-filter=d 2>/dev/null | while read -r f; do
  if [ -f "$f" ]; then
    sz=$(wc -c < "$f" | tr -d ' ')
    if [ "$sz" -gt 1048576 ]; then
      echo "  $f ($(( sz / 1024 )) KB)"
    fi
  fi
done)
if [ -z "$large_files" ]; then
  ok "No large files in staged changes"
else
  echo "$large_files"
  die "Large files detected — consider Git LFS or splitting the change"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "========================"
if [ "$fail" -eq 0 ]; then
  echo "✅ All $pass pre-PR checks passed!"
  exit 0
else
  echo "❌ $fail of $((pass + fail)) checks failed."
  exit 1
fi
