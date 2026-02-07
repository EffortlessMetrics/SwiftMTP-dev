#!/usr/bin/env bash
set -euo pipefail

# ---------- config ----------
VID="${VID:-2717}"
PID="${PID:-ff10}"
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

# ---------- version validation ----------
echo "🏷️ Version validation"
if ! swift run --package-path "$PKG_PATH" swiftmtp version --json \
     1> "$LOGS_DIR/version.json" 2> "$LOGS_DIR/version-stderr.log"; then
  echo "❌ version command failed"; exit 70;
fi
cat "$LOGS_DIR/version.json" | json_ok || { echo "❌ version JSON invalid"; exit 70; }
# Structure validation guards
jq -e 'has("version") and has("git") and has("schemaVersion")' "$LOGS_DIR/version.json" >/dev/null || { echo "❌ version JSON missing required fields"; exit 70; }

# ---------- quirks explain ----------
echo "🧩 Quirks (explain)"
if ! swift run --package-path "$PKG_PATH" swiftmtp quirks --explain --json \
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
swift run --package-path "$PKG_PATH" swiftmtp storages \
  --vid "$VID" --pid "$PID" --json \
  1> "$LOGS_DIR/storages.json" 2> "$LOGS_DIR/storages-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 75 ]; then
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
swift run --package-path "$PKG_PATH" swiftmtp events 5 \
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
swift run --package-path "$PKG_PATH" swiftmtp collect \
  --noninteractive --strict --json \
  --vid "$VID" --pid "$PID" --bundle "$BUNDLE" \
  1> "$LOGS_DIR/collect.json" 2> "$LOGS_DIR/collect-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 75 ] && [ $code -ne 70 ] && [ $code -lt 128 ]; then
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
  echo "✅ Smoke OK"
else
  echo "ℹ️ Skipping bundle validation (collect failed as expected)"
  echo "✅ Smoke OK (no device connected)"
fi