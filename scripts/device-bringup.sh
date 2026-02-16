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
  --notes <text>          Optional run notes saved to mode.json
  -h, --help              Show this help
USAGE
}

MODE_LABEL=""
OUT_ROOT="Docs/benchmarks/device-bringup"
PACKAGE_PATH="SwiftMTPKit"
TARGET_VID=""
TARGET_PID=""
TARGET_BUS=""
TARGET_ADDRESS=""
MODE_NOTES=""

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

cat > "$RUN_DIR/summary.md" <<SUMMARY
# Device Bring-Up Summary

- Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Mode: \`${MODE_LABEL}\`
- device-lab exit code: \`${LAB_RC}\`

## Evidence

- Preflight checklist: \`${action_checklist}\`
- Host USB truth: \`${HOST_DIR}/system-profiler-usb.json\`
- SwiftMTP USB dump: \`${HOST_DIR}/swiftmtp-usb-dump.txt\`
- Device lab JSON output: \`${LOG_DIR}/device-lab.stdout.json\`
- Device lab artifacts: \`${LAB_DIR}\`

## Next

- Use \`${LAB_DIR}/connected-lab.md\` as the per-run matrix summary.
- Copy verified outcomes into a device page under \`Docs/SwiftMTP.docc/Devices/\`.
SUMMARY

if [[ $LAB_RC -eq 0 ]]; then
  echo "Bring-up run complete: $RUN_DIR"
else
  echo "Bring-up run captured diagnostics with non-zero result: $RUN_DIR"
fi

exit $LAB_RC
