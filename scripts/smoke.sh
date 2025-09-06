#!/usr/bin/env bash
set -euo pipefail

# Change to the SwiftMTPKit directory where Package.swift is located
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
cd SwiftMTPKit

VID="${VID:-2717}"; PID="${PID:-ff10}"
JSONQ='jq . > /dev/null' # fail if not JSON

echo "🔧 Build"
swift build -c debug > /dev/null

echo "🧩 Quirks explain (JSON)"
swift run swiftmtp quirks --explain --json 2>"$PROJECT_ROOT/logs/quirks-stderr.log" | eval "$JSONQ"

echo "🔎 Probe (targeted, JSON)"
if ! swift run swiftmtp probe --noninteractive --vid "$VID" --pid "$PID" --json 2>/dev/null | eval "$JSONQ"; then
  echo "No matching device (expected 69 on CI w/o hardware)"; exit 69
fi

echo "💾 Storages"
swift run swiftmtp storages --vid "$VID" --pid "$PID" --json 2>/dev/null | eval "$JSONQ"

echo "📂 Listing"
swift run swiftmtp ls --vid "$VID" --pid "$PID" --json 2>/dev/null | eval "$JSONQ"

echo "📡 Events (5s)"
swift run swiftmtp events 5 --vid "$VID" --pid "$PID" --json 2>/dev/null | eval "$JSONQ"

echo "🗂️ Collect (bundle, strict, JSON)"
BUNDLE="$PROJECT_ROOT/Contrib/submissions/smoke-$VID-$PID-$(date +%Y%m%d-%H%M%S)"
swift run swiftmtp collect --noninteractive --strict --vid "$VID" --pid "$PID" --bundle "$BUNDLE" --json 2>/dev/null | eval "$JSONQ"
"$PROJECT_ROOT/scripts/validate-submission.sh" "$BUNDLE"

echo "✅ Smoke OK"
