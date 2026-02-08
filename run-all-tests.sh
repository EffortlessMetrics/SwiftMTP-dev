#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
RUN_KIT_TESTS="${RUN_KIT_TESTS:-1}"
RUN_XCODE_TESTS="${RUN_XCODE_TESTS:-1}"
RUN_XCODE_UI_TESTS="${RUN_XCODE_UI_TESTS:-0}"

if [[ "$RUN_KIT_TESTS" != "0" ]]; then
  printf 'Running SwiftMTPKit test matrix...\n'
  "$REPO_ROOT/SwiftMTPKit/run-all-tests.sh"
fi

if [[ "$RUN_XCODE_TESTS" != "0" ]]; then
  printf '\nRunning Xcode app + unit tests...\n'
  if [[ "$RUN_XCODE_UI_TESTS" == "0" ]]; then
    printf 'Skipping SwiftMTPUITests (set RUN_XCODE_UI_TESTS=1 to include UI automation tests).\n'
    xcodebuild test \
      -project "$REPO_ROOT/SwiftMTP.xcodeproj" \
      -scheme SwiftMTP \
      -destination 'platform=macOS' \
      -skip-testing:SwiftMTPUITests
  else
    xcodebuild test \
      -project "$REPO_ROOT/SwiftMTP.xcodeproj" \
      -scheme SwiftMTP \
      -destination 'platform=macOS'
  fi
fi
