#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAP_FILE="Specs/ux/interaction-map.yaml"
UX_FLOW_FILE="SwiftMTPKit/Sources/SwiftMTPUI/UXFlowID.swift"
A11Y_FILE="SwiftMTPKit/Sources/SwiftMTPUI/AccessibilityID.swift"

cd "$REPO_ROOT"

determine_diff_range() {
  if [[ -n "${UX_TOUCH_DIFF_RANGE:-}" ]]; then
    echo "$UX_TOUCH_DIFF_RANGE"
    return
  fi

  if [[ -n "${GITHUB_BASE_REF:-}" ]] && git rev-parse --verify "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
    echo "origin/${GITHUB_BASE_REF}...HEAD"
    return
  fi

  if [[ -z "${GITHUB_ACTIONS:-}" ]] && ! git diff --quiet HEAD --; then
    echo "HEAD"
    return
  fi

  if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    echo "HEAD~1...HEAD"
    return
  fi

  echo ""
}

DIFF_RANGE="$(determine_diff_range)"
if [[ -z "$DIFF_RANGE" ]]; then
  echo "ℹ️  UX touch validation skipped (no diff range available)."
  exit 0
fi

CHANGED_FILES=()
while IFS= read -r changed; do
  CHANGED_FILES+=("$changed")
done < <(git diff --name-only "$DIFF_RANGE")

if [[ "$DIFF_RANGE" == "HEAD" ]]; then
  while IFS= read -r untracked; do
    CHANGED_FILES+=("$untracked")
  done < <(git ls-files --others --exclude-standard)
fi
if [[ "${#CHANGED_FILES[@]}" -eq 0 ]]; then
  echo "✅ UX touch validation skipped (no changed files)."
  exit 0
fi

is_ui_source_file() {
  local path="$1"
  [[ "$path" =~ ^SwiftMTPKit/Sources/SwiftMTPUI/.*\.swift$ ]]
}

UI_SOURCE_FILES=()
MAP_CHANGED=0
UX_FLOW_CHANGED=0
A11Y_CHANGED=0

for file in "${CHANGED_FILES[@]}"; do
  if [[ "$file" == "$MAP_FILE" ]]; then
    MAP_CHANGED=1
  fi
  if [[ "$file" == "$UX_FLOW_FILE" ]]; then
    UX_FLOW_CHANGED=1
  fi
  if [[ "$file" == "$A11Y_FILE" ]]; then
    A11Y_CHANGED=1
  fi
  if is_ui_source_file "$file"; then
    UI_SOURCE_FILES+=("$file")
  fi
done

if [[ "${#UI_SOURCE_FILES[@]}" -eq 0 && "$MAP_CHANGED" -eq 0 && "$UX_FLOW_CHANGED" -eq 0 && "$A11Y_CHANGED" -eq 0 ]]; then
  echo "✅ UX touch validation skipped (no UX-related file changes)."
  exit 0
fi

ERRORS=()

if [[ "$UX_FLOW_CHANGED" -eq 1 && "$MAP_CHANGED" -eq 0 ]]; then
  ERRORS+=("Updated ${UX_FLOW_FILE} but ${MAP_FILE} was not updated.")
fi

if [[ "$A11Y_CHANGED" -eq 1 && "$MAP_CHANGED" -eq 0 ]]; then
  ERRORS+=("Updated ${A11Y_FILE} but ${MAP_FILE} was not updated.")
fi

if [[ "${#UI_SOURCE_FILES[@]}" -gt 0 && "$MAP_CHANGED" -eq 0 ]]; then
  ALLOWLIST_MATCHES="$(git diff -U0 "$DIFF_RANGE" -- "${UI_SOURCE_FILES[@]}" | rg -c '^\+.*UX-NO-MAP:\s*' || true)"
  if [[ "${ALLOWLIST_MATCHES:-0}" -eq 0 ]]; then
    ERRORS+=(
      "UX source files changed without updating ${MAP_FILE}. Add map entries or include a diff comment containing 'UX-NO-MAP: <reason>'."
    )
  fi
fi

if [[ "${#UI_SOURCE_FILES[@]}" -gt 0 ]]; then
  ADDED_INTERACTIVES="$(git diff -U0 "$DIFF_RANGE" -- "${UI_SOURCE_FILES[@]}" | rg -c '^\+.*(Button\(|Toggle\(|NavigationLink\(|TextField\(|SecureField\(|\.onTapGesture\b)' || true)"
  ADDED_A11Y_IDS="$(git diff -U0 "$DIFF_RANGE" -- "${UI_SOURCE_FILES[@]}" | rg -c '^\+.*\.accessibilityIdentifier\(' || true)"

  if [[ "${ADDED_INTERACTIVES:-0}" -gt 0 && "${ADDED_A11Y_IDS:-0}" -eq 0 ]]; then
    ERRORS+=(
      "Detected new interactive UI additions but no added accessibility identifiers. Add AccessibilityID-backed identifiers for new controls/states."
    )
  fi
fi

if [[ "${#ERRORS[@]}" -gt 0 ]]; then
  echo "❌ UX touch validation failed (${DIFF_RANGE}):"
  for error in "${ERRORS[@]}"; do
    echo "  - ${error}"
  done
  exit 1
fi

echo "✅ UX touch validation passed (${DIFF_RANGE})."
