#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# mutation-test.sh — Lightweight mutation testing harness for Swift sources
#
# Usage: ./scripts/mutation-test.sh <source-file> [--filter <test-filter>]
#
# Applies simple source-level mutations one at a time, runs the test suite,
# and reports which mutations were caught (test failure) vs survived (tests
# still pass, meaning tests may be weak for that code path).

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

usage() {
  echo "Usage: $0 <source-file> [--filter <test-filter>]"
  echo ""
  echo "Arguments:"
  echo "  <source-file>   Swift source file to mutate"
  echo "  --filter         XCTest filter to run (default: CoreTests)"
  echo ""
  echo "Examples:"
  echo "  $0 Sources/SwiftMTPCore/Public/MTPDevice.swift"
  echo "  $0 Sources/SwiftMTPCore/Internal/Protocol/PTPCodec.swift --filter PTPCodecTests"
  exit 1
}

# ── Parse arguments ──────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage

SOURCE_FILE="$1"
shift

TEST_FILTER="CoreTests"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) TEST_FILTER="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo -e "${RED}Error: File not found: ${SOURCE_FILE}${NC}"
  exit 1
fi

# ── Mutation definitions ─────────────────────────────────────────────────────
# Each mutation is a pair: (sed pattern, human description).
# We use | as sed delimiter to avoid escaping slashes.

declare -a MUT_PATTERNS
declare -a MUT_DESCRIPTIONS

add_mutation() {
  MUT_PATTERNS+=("$1")
  MUT_DESCRIPTIONS+=("$2")
}

# Boolean swaps
add_mutation 's|return true|return false|'           "swap 'return true' → 'return false'"
add_mutation 's|return false|return true|'           "swap 'return false' → 'return true'"
add_mutation 's|== true|== false|'                   "swap '== true' → '== false'"
add_mutation 's|== false|== true|'                   "swap '== false' → '== true'"

# Boundary condition swaps
add_mutation 's| < | <= |'                           "swap '<' → '<='"
add_mutation 's| <= | < |'                           "swap '<=' → '<'"
add_mutation 's| > | >= |'                           "swap '>' → '>='"
add_mutation 's| >= | > |'                           "swap '>=' → '>'"

# Arithmetic swaps
add_mutation 's| + | - |'                            "swap '+' → '-'"
add_mutation 's| - | + |'                            "swap '-' → '+'"
add_mutation 's| \* | / |'                           "swap '*' → '/'"

# Nil/optional swaps
add_mutation 's|!= nil|== nil|'                      "swap '!= nil' → '== nil'"
add_mutation 's|== nil|!= nil|'                      "swap '== nil' → '!= nil'"

# Return removal (replace return X with return)
add_mutation 's|return \(nil\)|return Optional<Any>.none as! Never|' "replace 'return nil' → crash"

# Guard else return → guard else (noop break)
add_mutation 's|else { return nil }|else { return nil; /* mutant */ }|' "tag guard-return (baseline check)"

# ── Backup ───────────────────────────────────────────────────────────────────

BACKUP="${SOURCE_FILE}.mutation-backup"
cp "$SOURCE_FILE" "$BACKUP"

cleanup() {
  if [[ -f "$BACKUP" ]]; then
    cp "$BACKUP" "$SOURCE_FILE"
    rm -f "$BACKUP"
  fi
  echo -e "\n${CYAN}Original file restored.${NC}"
}
trap cleanup EXIT

# ── Baseline ─────────────────────────────────────────────────────────────────

echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Mutation Testing: ${SOURCE_FILE}${NC}"
echo -e "${CYAN}  Test filter:      ${TEST_FILTER}${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}▸ Running baseline tests…${NC}"

if ! swift test --filter "$TEST_FILTER" > /dev/null 2>&1; then
  echo -e "${RED}✗ Baseline tests fail — fix tests before running mutation testing.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Baseline tests pass.${NC}"
echo ""

# ── Run mutations ────────────────────────────────────────────────────────────

TOTAL=0
KILLED=0
SURVIVED=0
SKIPPED=0

for i in "${!MUT_PATTERNS[@]}"; do
  pattern="${MUT_PATTERNS[$i]}"
  desc="${MUT_DESCRIPTIONS[$i]}"

  # Restore original before each mutation
  cp "$BACKUP" "$SOURCE_FILE"

  # Check if mutation actually changes the file
  if ! sed "$pattern" "$SOURCE_FILE" | diff -q - "$SOURCE_FILE" > /dev/null 2>&1; then
    # File would change — apply the mutation
    sed -i '' "$pattern" "$SOURCE_FILE"
    TOTAL=$((TOTAL + 1))

    echo -ne "${YELLOW}▸ Mutant #${TOTAL}: ${desc}…${NC} "

    if swift test --filter "$TEST_FILTER" > /dev/null 2>&1; then
      echo -e "${RED}SURVIVED${NC}"
      SURVIVED=$((SURVIVED + 1))
    else
      echo -e "${GREEN}KILLED${NC}"
      KILLED=$((KILLED + 1))
    fi
  else
    # Mutation doesn't apply to this file — skip silently
    SKIPPED=$((SKIPPED + 1))
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Mutation Testing Summary${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "  Source:     ${SOURCE_FILE}"
echo -e "  Filter:     ${TEST_FILTER}"
echo -e "  Mutants:    ${TOTAL} applied (${SKIPPED} skipped — not applicable)"
echo -e "  ${GREEN}Killed:     ${KILLED}${NC}"
echo -e "  ${RED}Survived:   ${SURVIVED}${NC}"

if [[ $TOTAL -gt 0 ]]; then
  SCORE=$(( (KILLED * 100) / TOTAL ))
  echo -e "  Score:      ${SCORE}%"
  if [[ $SCORE -ge 80 ]]; then
    echo -e "  ${GREEN}✓ Mutation score is acceptable (≥80%).${NC}"
  else
    echo -e "  ${RED}✗ Mutation score is low (<80%). Consider adding more targeted tests.${NC}"
  fi
else
  echo -e "  ${YELLOW}No applicable mutations found in this file.${NC}"
fi
echo ""
