#!/usr/bin/env bash

# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.

set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  ./scripts/validate-mtp-unlocked.sh <connected-lab.json> --expect <vidpid> [--expect <vidpid> ...]

Example:
  ./scripts/validate-mtp-unlocked.sh /tmp/run/device-lab/connected-lab.json \
    --expect 04e8:6860 --expect 2717:ff40 --expect 18d1:4ee1 --expect 2a70:f003
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

REPORT_PATH="$1"
shift

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "❌ connected-lab report not found: $REPORT_PATH" >&2
  exit 66
fi

EXPECT_VIDPIDS=()
to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect)
      if [[ $# -lt 2 ]]; then
        echo "❌ --expect requires a VID:PID argument" >&2
        usage
        exit 64
      fi
      EXPECT_VIDPIDS+=("$(to_lower "$2")")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ ${#EXPECT_VIDPIDS[@]} -eq 0 ]]; then
  echo "❌ At least one --expect <vidpid> is required" >&2
  usage
  exit 64
fi

if ! jq -e '.devices and (.devices | type == "array")' "$REPORT_PATH" > /dev/null; then
  echo "❌ Invalid connected-lab JSON structure: $REPORT_PATH" >&2
  exit 65
fi

declare -i FAILURES=0

echo "Validating mtp-unlocked strict gates: $REPORT_PATH"

for expected in "${EXPECT_VIDPIDS[@]}"; do
  device_json="$(jq -c --arg vidpid "$expected" '.devices[] | select((.vidpid | ascii_downcase) == $vidpid)' "$REPORT_PATH" | head -n 1)"

  if [[ -z "$device_json" ]]; then
    echo "$expected FAIL missing-device"
    FAILURES+=1
    continue
  fi

  open_ok="$(jq -r '.read.openSucceeded // false' <<< "$device_json")"
  info_ok="$(jq -r '.read.deviceInfoSucceeded // false' <<< "$device_json")"
  storage_count="$(jq -r '.read.storageCount // 0' <<< "$device_json")"
  root_ok="$(jq -r '.read.rootListingSucceeded // false' <<< "$device_json")"
  write_ok="$(jq -r '.write.succeeded // false' <<< "$device_json")"
  delete_ok="$(jq -r '.write.deleteSucceeded // false' <<< "$device_json")"

  missing=()
  [[ "$open_ok" == "true" ]] || missing+=("open")
  [[ "$info_ok" == "true" ]] || missing+=("deviceInfo")
  if ! [[ "$storage_count" =~ ^[0-9]+$ ]] || (( storage_count <= 0 )); then
    missing+=("storageCount>0")
  fi
  [[ "$root_ok" == "true" ]] || missing+=("rootList")
  [[ "$write_ok" == "true" ]] || missing+=("write")
  [[ "$delete_ok" == "true" ]] || missing+=("delete")

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "$expected PASS open=$open_ok deviceInfo=$info_ok storageCount=$storage_count rootList=$root_ok write=$write_ok delete=$delete_ok"
  else
    echo "$expected FAIL open=$open_ok deviceInfo=$info_ok storageCount=$storage_count rootList=$root_ok write=$write_ok delete=$delete_ok missing=$(IFS=,; echo "${missing[*]}")"
    FAILURES+=1
  fi
done

if (( FAILURES > 0 )); then
  echo "❌ Strict mtp-unlocked validation failed for $FAILURES device(s)."
  exit 1
fi

echo "✅ Strict mtp-unlocked validation passed."
