#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COVERAGE_DIR="${COVERAGE_DIR:-coverage}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-100}"
COVERAGE_MODULES="${COVERAGE_MODULES:-SwiftMTPQuirks,SwiftMTPStore,SwiftMTPSync,SwiftMTPObservability}"
RUN_FUZZ_SMOKE="${RUN_FUZZ_SMOKE:-1}"
RUN_STORYBOOK_SMOKE="${RUN_STORYBOOK_SMOKE:-1}"
RUN_SNAPSHOT_REFERENCE="${RUN_SNAPSHOT_REFERENCE:-1}"
DEFAULT_STORYBOOK_PROFILES="${STORYBOOK_PROFILE:-pixel7,galaxy,iphone,canon}"
STORYBOOK_PROFILES="${STORYBOOK_PROFILES:-$DEFAULT_STORYBOOK_PROFILES}"

mkdir -p "$COVERAGE_DIR"

printf 'Running full SwiftMTPKit test suite with coverage...\n'
printf 'Swift test matrix includes: BDD + property + fuzz + integration + unit + e2e + snapshot + storybook.\n'
if [[ "$RUN_SNAPSHOT_REFERENCE" != "0" ]]; then
  export SWIFTMTP_SNAPSHOT_TESTS=1
  printf 'Snapshot reference assertions: enabled.\n'
else
  unset SWIFTMTP_SNAPSHOT_TESTS || true
  printf 'Snapshot reference assertions: disabled (set RUN_SNAPSHOT_REFERENCE=1 to enable).\n'
fi
swift test --enable-code-coverage 2>&1 | tee "$COVERAGE_DIR/test_output.log"

COVERAGE_JSON_PATH="$(swift test --show-codecov-path)"

printf '\nEvaluating filtered coverage gate...\n'
python3 "$SCRIPT_DIR/scripts/coverage_gate.py" \
  --coverage-json "$COVERAGE_JSON_PATH" \
  --modules "$COVERAGE_MODULES" \
  --threshold "$COVERAGE_THRESHOLD" \
  --output-json "$COVERAGE_DIR/coverage.json" \
  --output-text "$COVERAGE_DIR/summary.txt"

if [[ "$RUN_FUZZ_SMOKE" != "0" ]]; then
  printf '\nRunning fuzz smoke tests (PTPCodecFuzzTests)...\n'
  swift test --skip-build --filter PTPCodecFuzzTests 2>&1 | tee "$COVERAGE_DIR/fuzz_output.log"
fi

if [[ "$RUN_STORYBOOK_SMOKE" != "0" ]]; then
  printf '\nRunning storybook smoke (profiles: %s)...\n' "$STORYBOOK_PROFILES"
  : > "$COVERAGE_DIR/storybook_output.log"
  IFS=',' read -r -a STORYBOOK_PROFILE_LIST <<< "$STORYBOOK_PROFILES"
  for raw_profile in "${STORYBOOK_PROFILE_LIST[@]}"; do
    profile="$(printf '%s' "$raw_profile" | xargs)"
    [[ -z "$profile" ]] && continue
    printf '\n=== Storybook profile: %s ===\n' "$profile" | tee -a "$COVERAGE_DIR/storybook_output.log"
    SWIFTMTP_MOCK_PROFILE="$profile" \
      swift run --skip-build swiftmtp storybook 2>&1 | tee -a "$COVERAGE_DIR/storybook_output.log"
  done
fi

printf '\nCoverage artifacts:\n'
printf '  - %s\n' "$COVERAGE_DIR/test_output.log"
printf '  - %s\n' "$COVERAGE_DIR/summary.txt"
printf '  - %s\n' "$COVERAGE_DIR/coverage.json"
if [[ "$RUN_FUZZ_SMOKE" != "0" ]]; then
  printf '  - %s\n' "$COVERAGE_DIR/fuzz_output.log"
fi
if [[ "$RUN_STORYBOOK_SMOKE" != "0" ]]; then
  printf '  - %s\n' "$COVERAGE_DIR/storybook_output.log"
fi
