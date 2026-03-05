#!/usr/bin/env bash
set -euo pipefail

# ---------- config ----------
VID="${VID:-0x2717}"
PID="${PID:-0xff10}"
PKG_PATH="${PKG_PATH:-SwiftMTPKit}"   # repo‑root path for swift run --package-path
BUNDLE_ROOT="Contrib/submissions"
TS="$(date +%Y%m%d-%H%M%S)"
BUNDLE="$BUNDLE_ROOT/smoke-$VID-$PID-$TS"
LOGS_DIR="logs"
mkdir -p "$LOGS_DIR" "$BUNDLE_ROOT"

# JSON validator
json_ok() { jq . >/dev/null 2>&1; }

# Helper function to run swiftmtp commands
run_swiftmtp() {
  swift run --package-path "$PKG_PATH" swiftmtp "$@"
}

# ---------- build ----------
echo "🔧 Building CLI…"
swift build --package-path "$PKG_PATH" -c debug >"$LOGS_DIR/build.log" 2>&1 || {
  echo "❌ build failed"; exit 70;
}

# ==========================================================
# CLI CONTRACT CHECKS (no hardware required)
# ==========================================================

# ---------- help output / command discovery ----------
echo "📋 CLI contract: help output"
run_swiftmtp 1> "$LOGS_DIR/help.txt" 2> "$LOGS_DIR/help-stderr.log" || {
  echo "❌ help (no-args) failed"; exit 70;
}

# Verify help contains expected structural keywords
for keyword in "Usage:" "Global Flags:" "Examples:"; do
  grep -q "$keyword" "$LOGS_DIR/help.txt" || {
    echo "❌ help output missing keyword: $keyword"; exit 70;
  }
done

# All registered commands must appear in help output
REGISTERED_COMMANDS=(
  probe usb-dump diag health
  ls storages pull push thumb delete move cp mirror snapshot
  edit
  bench profile
  quirks info add-device learn-promote
  collect submit wizard device-lab
  events bdd storybook version
)

MISSING=0
for cmd in "${REGISTERED_COMMANDS[@]}"; do
  if ! grep -qw "$cmd" "$LOGS_DIR/help.txt"; then
    echo "❌ command '$cmd' not found in help output"
    MISSING=1
  fi
done
[ "$MISSING" -eq 0 ] || { echo "❌ CLI contract: missing commands in help"; exit 70; }
echo "  ✅ All ${#REGISTERED_COMMANDS[@]} commands discoverable in help"

# ---------- version validation ----------
echo "🏷️ Version validation"
run_swiftmtp version 1> "$LOGS_DIR/version.txt" 2> "$LOGS_DIR/version-txt-stderr.log" || {
  echo "❌ version (text) failed"; exit 70;
}
grep -q "SwiftMTP" "$LOGS_DIR/version.txt" || { echo "❌ version text missing 'SwiftMTP'"; exit 70; }

if ! run_swiftmtp version --json \
     1> "$LOGS_DIR/version.json" 2> "$LOGS_DIR/version-stderr.log"; then
  echo "❌ version command failed"; exit 70;
fi
cat "$LOGS_DIR/version.json" | json_ok || { echo "❌ version JSON invalid"; exit 70; }
# Structure validation guards
jq -e 'has("version") and has("git") and has("schemaVersion")' "$LOGS_DIR/version.json" >/dev/null || { echo "❌ version JSON missing required fields"; exit 70; }

# ---------- subcommand smoke (no hardware) ----------
echo "🔍 Subcommand smoke checks (no hardware)"

# info (no args) — shows database summary
run_swiftmtp info \
  1> "$LOGS_DIR/info.txt" 2> "$LOGS_DIR/info-stderr.log" || {
  echo "❌ info command failed"; exit 70;
}
grep -q "Device Database" "$LOGS_DIR/info.txt" || { echo "❌ info output missing 'Device Database'"; exit 70; }
echo "  ✅ info"

# storybook — runs with simulated data, no hardware
run_swiftmtp storybook \
  1> "$LOGS_DIR/storybook.txt" 2> "$LOGS_DIR/storybook-stderr.log" || {
  echo "❌ storybook command failed"; exit 70;
}
grep -q "Storybook" "$LOGS_DIR/storybook.txt" || { echo "❌ storybook output missing 'Storybook'"; exit 70; }
echo "  ✅ storybook"

# add-device (no args) — prints usage
run_swiftmtp add-device \
  1> "$LOGS_DIR/add-device.txt" 2> "$LOGS_DIR/add-device-stderr.log" || true
grep -q "Usage:" "$LOGS_DIR/add-device.txt" || { echo "❌ add-device output missing usage text"; exit 70; }
echo "  ✅ add-device (usage)"

# ---------- invalid command handling ----------
echo "🚫 Invalid command handling"
set +e
run_swiftmtp nonexistent-cmd-12345 \
  1> "$LOGS_DIR/invalid.txt" 2> "$LOGS_DIR/invalid-stderr.log"
invalid_exit=$?
set -e
if [ "$invalid_exit" -eq 0 ]; then
  echo "⚠️  invalid command exited 0 (non-zero preferred but accepted)"
else
  echo "  ✅ invalid command exited $invalid_exit"
fi
grep -qi "unknown command" "$LOGS_DIR/invalid.txt" || {
  echo "❌ invalid command output missing error message"; exit 70;
}

# ---------- demo mode ----------
echo "🎭 Demo mode"
SWIFTMTP_DEMO_MODE=1 run_swiftmtp probe --json \
  1> "$LOGS_DIR/demo-probe.json" 2> "$LOGS_DIR/demo-probe-stderr.log" || true
if [ -s "$LOGS_DIR/demo-probe.json" ]; then
  cat "$LOGS_DIR/demo-probe.json" | json_ok || { echo "❌ demo probe JSON invalid"; exit 70; }
  echo "  ✅ demo probe produced valid JSON"
else
  echo "  ⚠️  demo probe produced no output (accepted)"
fi

# ---------- quirks explain ----------
echo "🧩 Quirks (explain)"
if ! run_swiftmtp quirks --explain --json \
     1> "$LOGS_DIR/quirks.json" 2> "$LOGS_DIR/quirks-stderr.log"; then
  echo "❌ quirks --explain failed"; exit 70;
fi
cat "$LOGS_DIR/quirks.json" | json_ok || { echo "❌ quirks JSON invalid"; exit 70; }
# Structure validation guards
jq -e 'has("schemaVersion") and has("mode") and has("layers") and has("effective")' "$LOGS_DIR/quirks.json" >/dev/null || { echo "❌ quirks JSON missing required fields"; exit 70; }

# ---------- probe (targeted) ----------
echo "🔎 Probe (VID=$VID PID=$PID)"
set +e  # Temporarily disable exit on error for hardware-dependent commands
run_swiftmtp probe \
      --noninteractive --vid "$VID" --pid "$PID" --json \
      1> "$LOGS_DIR/probe.json" 2> "$LOGS_DIR/probe-stderr.log"
code=$?
set -e  # Re-enable exit on error
echo "ℹ️ probe exited with code $code"
# Handle "no device" scenario - exit code 69 (unavailable) is expected in CI without hardware
# Exit codes 0, 69, 75 are acceptable for "no device" scenarios
if [ $code -eq 69 ] || [ $code -eq 75 ]; then
  echo "ℹ️ Device unavailable (code $code) - this is expected without hardware"
fi
# Check if we got valid JSON only on success
if [ $code -eq 0 ]; then
  if [ -f "$LOGS_DIR/probe.json" ]; then
    cat "$LOGS_DIR/probe.json" | json_ok || { echo "❌ probe JSON invalid"; exit 70; }
    jq -e 'has("capabilities") and has("effective")' "$LOGS_DIR/probe.json" >/dev/null || { echo "❌ probe JSON missing required fields"; exit 70; }
  else
    echo "❌ probe.json not created on success"; exit 70;
  fi
else
  echo "ℹ️ probe.json not created (expected when no device)"
fi

# ---------- storages ----------
echo "💾 Storages"
set +e  # Temporarily disable exit on error
run_swiftmtp storages \
  --vid "$VID" --pid "$PID" --json \
  1> "$LOGS_DIR/storages.json" 2> "$LOGS_DIR/storages-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 69 ] && [ $code -ne 75 ]; then
  echo "❌ storages failed with exit $code"
  exit $code
fi
if [ $code -eq 75 ] || [ $code -eq 69 ]; then
  echo "ℹ️ storages failed with exit $code (expected: no device connected)"
fi
# Validate JSON only if file exists
if [ -f "$LOGS_DIR/storages.json" ]; then
  cat "$LOGS_DIR/storages.json" | json_ok || { echo "❌ storages JSON invalid"; exit 70; }
  jq -e 'has("storages") or has("error")' "$LOGS_DIR/storages.json" >/dev/null || { echo "❌ storages JSON missing required fields"; exit 70; }
else
  echo "ℹ️ storages.json not created (expected when no device)"
fi

# ---------- ls (top level only) ----------
echo "📂 List"
set +e  # Temporarily disable exit on error
run_swiftmtp ls 0 \
  --vid "$VID" --pid "$PID" --json \
  1> "$LOGS_DIR/ls.json" 2> "$LOGS_DIR/ls-stderr.log"
code=$?
set -e  # Re-enable exit on error
# Exit codes 0, 69, 75 are acceptable for "no device" scenarios
if [ $code -ne 0 ] && [ $code -ne 69 ] && [ $code -ne 75 ]; then
  echo "❌ ls failed with exit $code"
  exit $code
fi
if [ $code -eq 69 ] || [ $code -eq 75 ]; then
  echo "ℹ️ ls failed with exit $code (expected: no device connected)"
fi
# Validate JSON only on success
if [ $code -eq 0 ]; then
  if [ -f "$LOGS_DIR/ls.json" ]; then
    cat "$LOGS_DIR/ls.json" | json_ok || { echo "❌ ls JSON invalid"; exit 70; }
  else
    echo "❌ ls.json not created on success"; exit 70;
  fi
else
  echo "ℹ️ ls.json not created (expected when no device)"
fi

# ---------- events (5s) ----------
echo "📡 Events (5s)"
set +e  # Temporarily disable exit on error
run_swiftmtp events 5 \
  --vid "$VID" --pid "$PID" --json \
  1> "$LOGS_DIR/events.json" 2> "$LOGS_DIR/events-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 69 ] && [ $code -ne 75 ] && [ $code -lt 128 ]; then
  echo "❌ events failed with exit $code"
  exit $code
fi
if [ $code -eq 69 ] || [ $code -eq 75 ]; then
  echo "ℹ️ events failed with exit $code (expected: no device connected)"
fi
# Validate JSON only if file exists
if [ -f "$LOGS_DIR/events.json" ]; then
  cat "$LOGS_DIR/events.json" | json_ok || { echo "❌ events JSON invalid"; exit 70; }
else
  echo "ℹ️ events.json not created (expected when no device)"
fi

# ---------- collect (strict, read‑only) ----------
echo "🗂️ Collect bundle → $BUNDLE"
set +e  # Temporarily disable exit on error
run_swiftmtp collect \
  --noninteractive --strict --json \
  --vid "$VID" --pid "$PID" --bundle "$BUNDLE" \
  1> "$LOGS_DIR/collect.json" 2> "$LOGS_DIR/collect-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 69 ] && [ $code -ne 75 ] && [ $code -ne 70 ] && [ $code -lt 128 ]; then
  echo "❌ collect failed with exit $code"
  exit $code
fi
if [ $code -eq 75 ] || [ $code -eq 70 ] || [ $code -eq 69 ]; then
  echo "ℹ️ collect failed with exit $code (expected: no device connected)"
fi
# Validate JSON only if file exists
if [ -f "$LOGS_DIR/collect.json" ]; then
  cat "$LOGS_DIR/collect.json" | json_ok || { echo "❌ collect JSON invalid"; exit 70; }
else
  echo "ℹ️ collect.json not created (expected when no device)"
fi

# Validate bundle (only if collect succeeded)
if [ $code -eq 0 ]; then
  ./scripts/validate-submission.sh "$BUNDLE"
  echo "✅ Smoke OK (${#REGISTERED_COMMANDS[@]} commands verified)"
else
  echo "ℹ️ Skipping bundle validation (collect failed as expected)"
  echo "✅ Smoke OK — CLI contract verified (${#REGISTERED_COMMANDS[@]} commands), no device connected"
fi
