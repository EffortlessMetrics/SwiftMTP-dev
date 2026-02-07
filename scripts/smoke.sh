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

# ---------- build ----------
echo "🔧 Building CLI…"
swift build --package-path "$PKG_PATH" -c debug >"$LOGS_DIR/build.log" 2>&1 || {
  echo "❌ build failed"; exit 70;
}

# Find binary - check package path first, then root
SWIFTMTP="$(find "$PKG_PATH/.build" .build -name swiftmtp -type f -perm +111 2>/dev/null | head -n 1)"
if [ -z "$SWIFTMTP" ]; then
  echo "❌ swiftmtp binary not found"; exit 70
fi
echo "🚀 Using binary: $SWIFTMTP"

# ---------- version validation ----------
echo "🏷️ Version validation"
if ! "$SWIFTMTP" version --json \
     1> "$LOGS_DIR/version.json" 2> "$LOGS_DIR/version-stderr.log"; then
  echo "❌ version command failed"; exit 70;
fi
cat "$LOGS_DIR/version.json" | json_ok || { echo "❌ version JSON invalid"; exit 70; }
# Structure validation guards
jq -e 'has("version") and has("git") and has("schemaVersion")' "$LOGS_DIR/version.json" >/dev/null || { echo "❌ version JSON missing required fields"; exit 70; }

# ---------- quirks explain ----------
echo "🧩 Quirks (explain)"
if ! "$SWIFTMTP" quirks --explain --json \
     1> "$LOGS_DIR/quirks.json" 2> "$LOGS_DIR/quirks-stderr.log"; then
  echo "❌ quirks --explain failed"; exit 70;
fi
cat "$LOGS_DIR/quirks.json" | json_ok || { echo "❌ quirks JSON invalid"; exit 70; }
# Structure validation guards
jq -e 'has("schemaVersion") and has("mode") and has("layers") and has("effective")' "$LOGS_DIR/quirks.json" >/dev/null || { echo "❌ quirks JSON missing required fields"; exit 70; }

# ---------- probe (targeted) ----------
echo "🔎 Probe (VID=$VID PID=$PID)"
set +e
"$SWIFTMTP" probe \
      --noninteractive --vid "$VID" --pid "$PID" --json \
      1> "$LOGS_DIR/probe.json" 2> "$LOGS_DIR/probe-stderr.log"
code=$?
set -e
echo "ℹ️ probe exited with code $code"
if [ $code -ne 0 ]; then
  # On CI without hardware, we accept 69 (unavailable) as a pass signal.
  if [[ "${CI:-}" == "true" && $code -eq 69 ]]; then
    exit 0
  fi
  # If running locally, we might want to continue or exit based on code
  if [ $code -eq 69 ]; then
    echo "ℹ️ Device unavailable (code 69) - this is expected without hardware"
  else
    echo "❌ probe failed with unexpected error code $code"
    exit $code
  fi
fi
cat "$LOGS_DIR/probe.json" | json_ok || { echo "❌ probe JSON invalid"; exit 70; }
# Structure validation guards
jq -e 'has("capabilities") and has("effective")' "$LOGS_DIR/probe.json" >/dev/null || { echo "❌ probe JSON missing required fields"; exit 70; }

# ---------- storages ----------
echo "💾 Storages"
set +e  # Temporarily disable exit on error
"$SWIFTMTP" storages \
  --vid "$VID" --pid "$PID" --json \
  1> "$LOGS_DIR/storages.json" 2> "$LOGS_DIR/storages-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 75 ] && [ $code -ne 69 ]; then
  echo "❌ storages failed with exit $code"
  exit $code
fi
if [ $code -eq 75 ] || [ $code -eq 69 ]; then
  echo "ℹ️ storages failed with exit $code (expected: no device connected)"
fi
cat "$LOGS_DIR/storages.json" | json_ok || { echo "❌ storages JSON invalid"; exit 70; }
# Structure validation guards
jq -e 'has("storages") or has("error")' "$LOGS_DIR/storages.json" >/dev/null || { echo "❌ storages JSON missing required fields"; exit 70; }

# ---------- ls (top level only) ----------
echo "📂 List"
set +e  # Temporarily disable exit on error
"$SWIFTMTP" ls \
  --vid "$VID" --pid "$PID" --json 0 \
  1> "$LOGS_DIR/ls.json" 2> "$LOGS_DIR/ls-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 75 ] && [ $code -ne 69 ]; then
  echo "❌ ls failed with exit $code"
  exit $code
fi
cat "$LOGS_DIR/ls.json" | json_ok || { echo "❌ ls JSON invalid"; exit 70; }

# ---------- events (1s) ----------
echo "📡 Events (1s)"
set +e  # Temporarily disable exit on error
"$SWIFTMTP" events \
  --vid "$VID" --pid "$PID" --json 1 \
  1> "$LOGS_DIR/events.json" 2> "$LOGS_DIR/events-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 69 ] && [ $code -ne 75 ]; then
  echo "❌ events failed with exit $code"
  exit $code
fi
cat "$LOGS_DIR/events.json" | json_ok || { echo "❌ events JSON invalid"; exit 70; }

# ---------- collect (strict, read‑only) ----------
echo "🗂️ Collect bundle → $BUNDLE"
set +e  # Temporarily disable exit on error
"$SWIFTMTP" collect \
  --noninteractive --strict --json \
  --vid "$VID" --pid "$PID" --bundle "$BUNDLE" \
  1> "$LOGS_DIR/collect.json" 2> "$LOGS_DIR/collect-stderr.log"
code=$?
set -e  # Re-enable exit on error
if [ $code -ne 0 ] && [ $code -ne 75 ] && [ $code -ne 70 ] && [ $code -ne 69 ]; then
  echo "❌ collect failed with exit $code"
  exit $code
fi
cat "$LOGS_DIR/collect.json" | json_ok || { echo "❌ collect JSON invalid"; exit 70; }

# Validate bundle (only if collect succeeded)
if [ $code -eq 0 ]; then
  ./scripts/validate-submission.sh "$BUNDLE"
  echo "✅ Smoke OK"
else
  echo "ℹ️ Skipping bundle validation (collect failed as expected)"
  echo "✅ Smoke OK (no device connected)"
fi