#!/usr/bin/env bash

# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.
#
# device-bringup.sh — Automated device bring-up and evidence capture
#
# Runs probe, info, ls, test-read, and collect stages against a connected
# MTP device and saves structured evidence (JSON + human-readable) to a
# timestamped directory.
#
# Usage:
#   ./scripts/device-bringup.sh --mode mtp-unlocked [--device 18d1:4ee1]
#   ./scripts/device-bringup.sh --mode mtp-unlocked --dry-run
#
# See Docs/DeviceBringup.md for the full guide.

set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  ./scripts/device-bringup.sh --mode <label> [options]

Options:
  --mode <label>          Required mode label (for example: mtp-unlocked, mtp-locked, ptp)
  --device <vid:pid>      Target a specific device by VID:PID (for example: 18d1:4ee1)
  --dry-run               Show what would be captured without running commands
  --out-root <path>       Output root (default: Docs/benchmarks/device-bringup)
  --package-path <path>   Swift package path (default: SwiftMTPKit)
  --vid <hex>             Device VID filter (for example: 0x18d1)
  --pid <hex>             Device PID filter (for example: 0x4ee1)
  --bus <int>             Device USB bus filter
  --address <int>         Device USB address filter
  --strict-unlocked       Run strict unlocked validator after device-lab
  --expect <vid:pid>      Expected device for strict validation (repeatable)
  --notes <text>          Optional run notes saved to mode.json
  -h, --help              Show this help
USAGE
}

normalize_usb_id() {
  local raw="${1:-}"
  raw="$(echo "$raw" | tr '[:upper:]' '[:lower:]')"
  raw="${raw// /}"
  raw="${raw#0x}"
  if [[ -z "$raw" ]]; then
    return 1
  fi

  if [[ "$raw" =~ ^[0-9a-f]+$ ]]; then
    printf "%04x" "$((16#$raw))"
    return 0
  fi

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf "%04x" "$((10#$raw))"
    return 0
  fi

  return 1
}

normalize_vidpid() {
  local raw="${1:-}"
  local vid pid norm_vid norm_pid
  if [[ "$raw" != *:* ]]; then
    return 1
  fi
  vid="${raw%%:*}"
  pid="${raw##*:}"
  norm_vid="$(normalize_usb_id "$vid")" || return 1
  norm_pid="$(normalize_usb_id "$pid")" || return 1
  printf "%s:%s" "$norm_vid" "$norm_pid"
}

MODE_LABEL=""
OUT_ROOT="Docs/benchmarks/device-bringup"
PACKAGE_PATH="SwiftMTPKit"
TARGET_VID=""
TARGET_PID=""
TARGET_BUS=""
TARGET_ADDRESS=""
MODE_NOTES=""
STRICT_UNLOCKED=false
DRY_RUN=false
EXPECT_VIDPIDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE_LABEL="${2:-}"
      shift 2
      ;;
    --device)
      if [[ $# -lt 2 || "${2:-}" != *:* ]]; then
        echo "--device requires a <vid:pid> value (for example: 18d1:4ee1)" >&2
        usage
        exit 64
      fi
      dev_vid="${2%%:*}"
      dev_pid="${2##*:}"
      TARGET_VID="$dev_vid"
      TARGET_PID="$dev_pid"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --out-root)
      OUT_ROOT="${2:-}"
      shift 2
      ;;
    --package-path)
      PACKAGE_PATH="${2:-}"
      shift 2
      ;;
    --vid)
      TARGET_VID="${2:-}"
      shift 2
      ;;
    --pid)
      TARGET_PID="${2:-}"
      shift 2
      ;;
    --bus)
      TARGET_BUS="${2:-}"
      shift 2
      ;;
    --address)
      TARGET_ADDRESS="${2:-}"
      shift 2
      ;;
    --strict-unlocked)
      STRICT_UNLOCKED=true
      shift
      ;;
    --expect)
      if [[ $# -lt 2 ]]; then
        echo "--expect requires a <vid:pid> value" >&2
        usage
        exit 64
      fi
      normalized_expect="$(normalize_vidpid "${2:-}")" || {
        echo "Invalid --expect value: ${2:-}" >&2
        usage
        exit 64
      }
      EXPECT_VIDPIDS+=("$normalized_expect")
      shift 2
      ;;
    --notes)
      MODE_NOTES="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -z "$MODE_LABEL" ]]; then
  echo "--mode is required" >&2
  usage
  exit 64
fi

if [[ "$STRICT_UNLOCKED" == "true" ]] && [[ ${#EXPECT_VIDPIDS[@]} -eq 0 ]]; then
  if [[ -n "$TARGET_VID" && -n "$TARGET_PID" ]]; then
    derived_vid="$(normalize_usb_id "$TARGET_VID")" || {
      echo "Could not normalize --vid value for strict mode: $TARGET_VID" >&2
      exit 64
    }
    derived_pid="$(normalize_usb_id "$TARGET_PID")" || {
      echo "Could not normalize --pid value for strict mode: $TARGET_PID" >&2
      exit 64
    }
    EXPECT_VIDPIDS+=("${derived_vid}:${derived_pid}")
  else
    echo "--strict-unlocked requires at least one --expect <vid:pid> (or both --vid and --pid)" >&2
    exit 64
  fi
fi

# --- dry-run: show plan and exit -------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  echo "== SwiftMTP Device Bring-Up (dry-run) =="
  echo "Mode:    $MODE_LABEL"
  echo "Device:  ${TARGET_VID:-(any)}:${TARGET_PID:-(any)}"
  echo ""
  echo "The following stages would execute:"
  echo "  1. Host snapshot       — sw_vers, uname, system_profiler SPUSBDataType"
  echo "  2. USB dump            — swiftmtp usb-dump"
  echo "  3. Probe (JSON)        — swiftmtp probe --json"
  echo "  4. Device info         — swiftmtp info"
  echo "  5. Storage listing     — swiftmtp ls"
  echo "  6. Test read           — download first file < 1 MB"
  echo "  7. Evidence collection — swiftmtp collect --json"
  echo "  8. Device lab          — swiftmtp device-lab connected --json"
  if [[ "$STRICT_UNLOCKED" == "true" ]]; then
    echo "  9. Strict validation   — validate-mtp-unlocked.sh"
  fi
  echo ""
  echo "Output would be saved to:"
  echo "  Docs/benchmarks/device-bringup/<timestamp>-${MODE_LABEL}/"
  exit 0
fi

# --- helpers ---------------------------------------------------------------
# Build a base command array with device filters applied.
build_swiftmtp_cmd() {
  local -a cmd=(swift run --package-path "$PACKAGE_PATH" swiftmtp)
  if [[ -n "$TARGET_VID" ]]; then cmd+=(--vid "$TARGET_VID"); fi
  if [[ -n "$TARGET_PID" ]]; then cmd+=(--pid "$TARGET_PID"); fi
  if [[ -n "$TARGET_BUS" ]]; then cmd+=(--bus "$TARGET_BUS"); fi
  if [[ -n "$TARGET_ADDRESS" ]]; then cmd+=(--address "$TARGET_ADDRESS"); fi
  printf '%s\n' "${cmd[@]}"
}

# Run a stage, capturing stdout and stderr. Non-fatal: logs failure and
# returns the exit code without aborting the script.
run_stage() {
  local label="$1" stdout_file="$2" stderr_file="$3"
  shift 3
  set +e
  "$@" > "$stdout_file" 2> "$stderr_file"
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "  ✅ $label"
  else
    echo "  ❌ $label (exit $rc — see $stderr_file)"
  fi
  return $rc
}

MODE_NOTES_JSON="${MODE_NOTES//\"/\\\"}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ "$OUT_ROOT" != /* ]]; then
  OUT_ROOT="${REPO_ROOT}/${OUT_ROOT}"
fi
if [[ "$PACKAGE_PATH" != /* ]]; then
  PACKAGE_PATH="${REPO_ROOT}/${PACKAGE_PATH}"
fi

MODE_SLUG="$(echo "$MODE_LABEL" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$OUT_ROOT/$TIMESTAMP-$MODE_SLUG"
HOST_DIR="$RUN_DIR/host"
LOG_DIR="$RUN_DIR/logs"
LAB_DIR="$RUN_DIR/device-lab"
EVIDENCE_DIR="$RUN_DIR/evidence"

mkdir -p "$HOST_DIR" "$LOG_DIR" "$LAB_DIR" "$EVIDENCE_DIR"

echo "== SwiftMTP Device Bring-Up =="
echo "Mode: $MODE_LABEL"
echo "Output: $RUN_DIR"

action_checklist="$RUN_DIR/preflight.md"
cat > "$action_checklist" <<'CHECKLIST'
# Preflight Checklist

- Close host apps that can grab camera/MTP interfaces (Photos, Android File Transfer, browser WebUSB tabs).
- Use a known-good USB data cable.
- Keep the device unlocked for first validation.
- Confirm phone USB mode before the run (File Transfer/MTP or PTP).
CHECKLIST

cat > "$RUN_DIR/mode.json" <<MODEJSON
{
  "modeLabel": "${MODE_LABEL}",
  "notes": "${MODE_NOTES_JSON}",
  "strictUnlocked": ${STRICT_UNLOCKED},
  "strictExpectations": [$(printf '"%s",' "${EXPECT_VIDPIDS[@]}" | sed 's/,$//')],
  "filters": {
    "vid": "${TARGET_VID}",
    "pid": "${TARGET_PID}",
    "bus": "${TARGET_BUS}",
    "address": "${TARGET_ADDRESS}"
  }
}
MODEJSON

sw_vers > "$HOST_DIR/sw-vers.txt"
uname -a > "$HOST_DIR/uname.txt"

if system_profiler SPUSBDataType -json > "$HOST_DIR/system-profiler-usb.json" 2> "$LOG_DIR/system-profiler.stderr.log"; then
  echo "  ✅ system_profiler USB snapshot"
else
  echo "  ⚠️  system_profiler capture failed (see $LOG_DIR/system-profiler.stderr.log)"
fi

# --- Stage 2: USB dump -----------------------------------------------------
USB_DUMP_CMD=(swift run --package-path "$PACKAGE_PATH" swiftmtp usb-dump)
run_stage "USB dump" "$HOST_DIR/swiftmtp-usb-dump.txt" "$LOG_DIR/usb-dump.stderr.log" \
  "${USB_DUMP_CMD[@]}" || true

# --- Stage 3: Probe (JSON) -------------------------------------------------
echo ""
echo "== Evidence Capture =="
PROBE_CMD=( $(build_swiftmtp_cmd) probe --json )
PROBE_RC=0
run_stage "Probe (JSON)" "$EVIDENCE_DIR/probe.json" "$LOG_DIR/probe.stderr.log" \
  "${PROBE_CMD[@]}" || PROBE_RC=$?

# Extract device metadata from probe JSON
PROBE_VID_PID=""
PROBE_MANUFACTURER=""
PROBE_MODEL=""
if [[ -f "$EVIDENCE_DIR/probe.json" && -s "$EVIDENCE_DIR/probe.json" ]]; then
  if command -v python3 &>/dev/null; then
    PROBE_VID_PID="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    devs = d if isinstance(d, list) else d.get('devices', [d])
    if devs:
        dev = devs[0]
        vid = dev.get('vendorId', dev.get('vid', ''))
        pid = dev.get('productId', dev.get('pid', ''))
        print(f'{vid}:{pid}')
except: pass
" < "$EVIDENCE_DIR/probe.json" 2>/dev/null)" || true
    PROBE_MANUFACTURER="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    devs = d if isinstance(d, list) else d.get('devices', [d])
    if devs:
        print(devs[0].get('manufacturer', devs[0].get('vendorName', '')))
except: pass
" < "$EVIDENCE_DIR/probe.json" 2>/dev/null)" || true
    PROBE_MODEL="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    devs = d if isinstance(d, list) else d.get('devices', [d])
    if devs:
        print(devs[0].get('model', devs[0].get('productName', devs[0].get('description', ''))))
except: pass
" < "$EVIDENCE_DIR/probe.json" 2>/dev/null)" || true
  fi
  if [[ -n "$PROBE_VID_PID" ]]; then
    echo "    VID:PID:      $PROBE_VID_PID"
  fi
  if [[ -n "$PROBE_MANUFACTURER" ]]; then
    echo "    Manufacturer: $PROBE_MANUFACTURER"
  fi
  if [[ -n "$PROBE_MODEL" ]]; then
    echo "    Model:        $PROBE_MODEL"
  fi
fi

# --- Stage 4: Device info --------------------------------------------------
INFO_CMD=( $(build_swiftmtp_cmd) info )
run_stage "Device info" "$EVIDENCE_DIR/info.txt" "$LOG_DIR/info.stderr.log" \
  "${INFO_CMD[@]}" || true

# --- Stage 5: Storage listing -----------------------------------------------
LS_CMD=( $(build_swiftmtp_cmd) ls )
run_stage "Storage listing" "$EVIDENCE_DIR/ls.txt" "$LOG_DIR/ls.stderr.log" \
  "${LS_CMD[@]}" || true

# --- Stage 6: Test read (first file < 1 MB) ---------------------------------
TEST_READ_STATUS="skipped"
TEST_READ_FILE=""
if [[ -f "$EVIDENCE_DIR/ls.txt" && -s "$EVIDENCE_DIR/ls.txt" ]]; then
  # Try to find a small file from ls output for a test read.
  # Heuristic: look for lines with file sizes < 1MB. Format varies; best-effort.
  TEST_READ_FILE="$(python3 -c "
import sys, re
for line in sys.stdin:
    line = line.strip()
    # Match common ls output patterns: size in bytes, then filename
    m = re.search(r'(\d+)\s+bytes?\s+(.+)', line)
    if m and int(m.group(1)) < 1048576 and int(m.group(1)) > 0:
        print(m.group(2).strip())
        break
    # Also try tab-separated: name <tab> size
    parts = line.split('\t')
    if len(parts) >= 2:
        try:
            sz = int(parts[-1].strip().replace(',', ''))
            if 0 < sz < 1048576:
                print(parts[0].strip())
                break
        except ValueError:
            pass
" < "$EVIDENCE_DIR/ls.txt" 2>/dev/null)" || true
  if [[ -n "$TEST_READ_FILE" ]]; then
    PULL_CMD=( $(build_swiftmtp_cmd) pull "$TEST_READ_FILE" "$EVIDENCE_DIR/test-read-file" )
    if run_stage "Test read ($TEST_READ_FILE)" \
        "$LOG_DIR/test-read.stdout.log" "$LOG_DIR/test-read.stderr.log" \
        "${PULL_CMD[@]}"; then
      TEST_READ_STATUS="passed"
    else
      TEST_READ_STATUS="failed"
    fi
  else
    echo "  ⏭  Test read skipped (no file < 1 MB found in listing)"
  fi
else
  echo "  ⏭  Test read skipped (no storage listing available)"
fi

# --- Stage 7: Evidence collection (collect --json) --------------------------
COLLECT_CMD=( $(build_swiftmtp_cmd) collect --json --noninteractive )
run_stage "Evidence collection" "$EVIDENCE_DIR/collect.json" "$LOG_DIR/collect.stderr.log" \
  "${COLLECT_CMD[@]}" || true

# --- Stage 8: Device lab ---------------------------------------------------
echo ""
echo "== Device Lab =="

LAB_CMD=( $(build_swiftmtp_cmd) device-lab connected --out "$LAB_DIR" --json )

set +e
"${LAB_CMD[@]}" > "$LOG_DIR/device-lab.stdout.json" 2> "$LOG_DIR/device-lab.stderr.log"
LAB_RC=$?
set -e

echo "device-lab exit code: $LAB_RC"

STRICT_RC=""
STRICT_STATUS="not-run"
if [[ "$STRICT_UNLOCKED" == "true" ]]; then
  REPORT_PATH="$LAB_DIR/connected-lab.json"
  if [[ $LAB_RC -ne 0 ]]; then
    STRICT_STATUS="skipped (device-lab failed)"
  elif [[ ! -f "$REPORT_PATH" ]]; then
    STRICT_STATUS="skipped (missing $REPORT_PATH)"
  else
    VALIDATE_CMD=("$REPO_ROOT/scripts/validate-mtp-unlocked.sh" "$REPORT_PATH")
    for expected in "${EXPECT_VIDPIDS[@]}"; do
      VALIDATE_CMD+=(--expect "$expected")
    done

    set +e
    "${VALIDATE_CMD[@]}" > "$LOG_DIR/validate-mtp-unlocked.stdout.log" 2> "$LOG_DIR/validate-mtp-unlocked.stderr.log"
    STRICT_RC=$?
    set -e

    if [[ $STRICT_RC -eq 0 ]]; then
      STRICT_STATUS="passed"
    else
      STRICT_STATUS="failed (exit $STRICT_RC)"
    fi
  fi
  echo "strict-unlocked validation: $STRICT_STATUS"
fi

FINAL_RC=$LAB_RC
if [[ "$STRICT_UNLOCKED" == "true" ]] && [[ $LAB_RC -eq 0 ]] && [[ -n "$STRICT_RC" ]] && [[ $STRICT_RC -ne 0 ]]; then
  FINAL_RC=$STRICT_RC
fi

cat > "$RUN_DIR/summary.md" <<SUMMARY
# Device Bring-Up Summary

- Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Mode: \`${MODE_LABEL}\`
- Device VID:PID: \`${PROBE_VID_PID:-unknown}\`
- Manufacturer: \`${PROBE_MANUFACTURER:-unknown}\`
- Model: \`${PROBE_MODEL:-unknown}\`
- device-lab exit code: \`${LAB_RC}\`
- test-read status: \`${TEST_READ_STATUS}\`
- strict-unlocked enabled: \`${STRICT_UNLOCKED}\`
- strict expectations: \`${EXPECT_VIDPIDS[*]:-none}\`
- strict validation status: \`${STRICT_STATUS}\`
- final exit code: \`${FINAL_RC}\`

## Evidence

- Preflight checklist: \`${action_checklist}\`
- Host USB truth: \`${HOST_DIR}/system-profiler-usb.json\`
- SwiftMTP USB dump: \`${HOST_DIR}/swiftmtp-usb-dump.txt\`
- Probe JSON: \`${EVIDENCE_DIR}/probe.json\`
- Device info: \`${EVIDENCE_DIR}/info.txt\`
- Storage listing: \`${EVIDENCE_DIR}/ls.txt\`
- Test read output: \`${LOG_DIR}/test-read.stdout.log\`
- Evidence collection: \`${EVIDENCE_DIR}/collect.json\`
- Device lab JSON output: \`${LOG_DIR}/device-lab.stdout.json\`
- Device lab artifacts: \`${LAB_DIR}\`
- Strict validator stdout: \`${LOG_DIR}/validate-mtp-unlocked.stdout.log\`
- Strict validator stderr: \`${LOG_DIR}/validate-mtp-unlocked.stderr.log\`

## Next

- Use \`${LAB_DIR}/connected-lab.md\` as the per-run matrix summary.
- Copy verified outcomes into a device page under \`Docs/SwiftMTP.docc/Devices/\`.
SUMMARY

# --- JSON summary -----------------------------------------------------------
cat > "$RUN_DIR/summary.json" <<SUMMARYJSON
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "mode": "${MODE_LABEL}",
  "device": {
    "vidPid": "${PROBE_VID_PID:-unknown}",
    "manufacturer": "${PROBE_MANUFACTURER:-unknown}",
    "model": "${PROBE_MODEL:-unknown}"
  },
  "stages": {
    "probe": ${PROBE_RC},
    "info": $(test -s "$EVIDENCE_DIR/info.txt" && echo 0 || echo 1),
    "ls": $(test -s "$EVIDENCE_DIR/ls.txt" && echo 0 || echo 1),
    "testRead": "${TEST_READ_STATUS}",
    "collect": $(test -s "$EVIDENCE_DIR/collect.json" && echo 0 || echo 1),
    "deviceLab": ${LAB_RC}
  },
  "strictUnlocked": ${STRICT_UNLOCKED},
  "strictExpectations": [$(printf '"%s",' "${EXPECT_VIDPIDS[@]}" | sed 's/,$//')],
  "strictStatus": "${STRICT_STATUS}",
  "exitCode": ${FINAL_RC},
  "evidenceDir": "${RUN_DIR}"
}
SUMMARYJSON

echo ""
if [[ $FINAL_RC -eq 0 ]]; then
  echo "✅ Bring-up run complete: $RUN_DIR"
else
  echo "⚠️  Bring-up run captured diagnostics with non-zero result: $RUN_DIR"
fi
echo "   Summary: $RUN_DIR/summary.json"

exit $FINAL_RC
