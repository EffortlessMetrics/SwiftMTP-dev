#!/usr/bin/env bash

# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.

set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  ./scripts/device-bringup.sh --mode <label> [options]

Options:
  --mode <label>          Required mode label (for example: mtp-unlocked, mtp-locked, ptp)
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
EXPECT_VIDPIDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE_LABEL="${2:-}"
      shift 2
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

mkdir -p "$HOST_DIR" "$LOG_DIR" "$LAB_DIR"

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
  echo "Captured system_profiler USB snapshot"
else
  echo "system_profiler capture failed (see $LOG_DIR/system-profiler.stderr.log)"
fi

USB_DUMP_CMD=(swift run --package-path "$PACKAGE_PATH" swiftmtp usb-dump)
if "${USB_DUMP_CMD[@]}" > "$HOST_DIR/swiftmtp-usb-dump.txt" 2> "$LOG_DIR/usb-dump.stderr.log"; then
  echo "Captured swiftmtp usb-dump"
else
  echo "swiftmtp usb-dump failed (see $LOG_DIR/usb-dump.stderr.log)"
fi

LAB_CMD=(swift run --package-path "$PACKAGE_PATH" swiftmtp)
if [[ -n "$TARGET_VID" ]]; then
  LAB_CMD+=(--vid "$TARGET_VID")
fi
if [[ -n "$TARGET_PID" ]]; then
  LAB_CMD+=(--pid "$TARGET_PID")
fi
if [[ -n "$TARGET_BUS" ]]; then
  LAB_CMD+=(--bus "$TARGET_BUS")
fi
if [[ -n "$TARGET_ADDRESS" ]]; then
  LAB_CMD+=(--address "$TARGET_ADDRESS")
fi
LAB_CMD+=(device-lab connected --out "$LAB_DIR" --json)

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
- device-lab exit code: \`${LAB_RC}\`
- strict-unlocked enabled: \`${STRICT_UNLOCKED}\`
- strict expectations: \`${EXPECT_VIDPIDS[*]:-none}\`
- strict validation status: \`${STRICT_STATUS}\`
- final exit code: \`${FINAL_RC}\`

## Evidence

- Preflight checklist: \`${action_checklist}\`
- Host USB truth: \`${HOST_DIR}/system-profiler-usb.json\`
- SwiftMTP USB dump: \`${HOST_DIR}/swiftmtp-usb-dump.txt\`
- Device lab JSON output: \`${LOG_DIR}/device-lab.stdout.json\`
- Device lab artifacts: \`${LAB_DIR}\`
- Strict validator stdout: \`${LOG_DIR}/validate-mtp-unlocked.stdout.log\`
- Strict validator stderr: \`${LOG_DIR}/validate-mtp-unlocked.stderr.log\`

## Next

- Use \`${LAB_DIR}/connected-lab.md\` as the per-run matrix summary.
- Copy verified outcomes into a device page under \`Docs/SwiftMTP.docc/Devices/\`.
SUMMARY

if [[ $FINAL_RC -eq 0 ]]; then
  echo "Bring-up run complete: $RUN_DIR"
else
  echo "Bring-up run captured diagnostics with non-zero result: $RUN_DIR"
fi

exit $FINAL_RC
