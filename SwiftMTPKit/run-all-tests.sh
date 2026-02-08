#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COVERAGE_DIR="${COVERAGE_DIR:-coverage}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-90}"
COVERAGE_MODULES="${COVERAGE_MODULES:-SwiftMTPQuirks,SwiftMTPStore,SwiftMTPSync,SwiftMTPObservability}"

mkdir -p "$COVERAGE_DIR"

printf 'Running full SwiftMTPKit test suite with coverage...\n'
swift test --enable-code-coverage 2>&1 | tee "$COVERAGE_DIR/test_output.log"

COVERAGE_JSON_PATH="$(swift test --show-codecov-path)"

printf '\nEvaluating filtered coverage gate...\n'
python3 "$SCRIPT_DIR/scripts/coverage_gate.py" \
  --coverage-json "$COVERAGE_JSON_PATH" \
  --modules "$COVERAGE_MODULES" \
  --threshold "$COVERAGE_THRESHOLD" \
  --output-json "$COVERAGE_DIR/coverage.json" \
  --output-text "$COVERAGE_DIR/summary.txt"

printf '\nCoverage artifacts:\n'
printf '  - %s\n' "$COVERAGE_DIR/test_output.log"
printf '  - %s\n' "$COVERAGE_DIR/summary.txt"
printf '  - %s\n' "$COVERAGE_DIR/coverage.json"
