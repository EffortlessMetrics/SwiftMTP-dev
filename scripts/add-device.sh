#!/usr/bin/env bash
set -euo pipefail

echo "🔌 SwiftMTP Device Entry Builder"
echo "================================"
echo ""

read -p "Vendor name (e.g., Samsung): " VENDOR
read -p "Device name (e.g., Galaxy S24): " DEVICE_NAME
read -p "Category (phone/camera/media-player/dev-board/etc): " CATEGORY
read -p "Vendor ID (hex, e.g., 04e8): " VID
read -p "Product ID (hex, e.g., 6860): " PID
read -p "Chunk size in bytes [1048576]: " CHUNK_SIZE
CHUNK_SIZE=${CHUNK_SIZE:-1048576}
read -p "Timeout in ms [8000]: " TIMEOUT
TIMEOUT=${TIMEOUT:-8000}
read -p "Supports getPartialObject? (y/n) [y]: " GET_PARTIAL
GET_PARTIAL=${GET_PARTIAL:-y}
read -p "Supports sendPartialObject? (y/n) [y]: " SEND_PARTIAL
SEND_PARTIAL=${SEND_PARTIAL:-y}

# Generate ID
VENDOR_LOWER=$(echo "$VENDOR" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
DEVICE_LOWER=$(echo "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
ID="${VENDOR_LOWER}-${DEVICE_LOWER}-${PID}"

GET_PARTIAL_BOOL=$([[ "$GET_PARTIAL" == "y" ]] && echo "true" || echo "false")
SEND_PARTIAL_BOOL=$([[ "$SEND_PARTIAL" == "y" ]] && echo "true" || echo "false")

echo ""
echo "Generated entry:"
echo "  ID: $ID"
echo "  VID:PID: 0x${VID}:0x${PID}"
echo ""

python3 << PYEOF
import json, sys

entry = {
    "id": "$ID",
    "deviceName": "$VENDOR $DEVICE_NAME",
    "category": "$CATEGORY",
    "match": {"vid": "0x$VID", "pid": "0x$PID"},
    "tuning": {"chunkSize": $CHUNK_SIZE, "timeoutMs": $TIMEOUT, "maxRetries": 3},
    "hooks": [],
    "ops": {"getPartialObject": $GET_PARTIAL_BOOL, "sendPartialObject": $SEND_PARTIAL_BOOL},
    "flags": {"noZeroLengthPackets": False},
    "status": "community",
    "confidence": "community"
}

with open("Specs/quirks.json") as f:
    d = json.load(f)

# Check for duplicates
for e in d["entries"]:
    if e["id"] == entry["id"]:
        print(f"❌ Entry with ID {entry['id']} already exists!")
        sys.exit(1)
    if e["match"]["vid"] == entry["match"]["vid"] and e["match"]["pid"] == entry["match"]["pid"]:
        print(f"❌ VID:PID 0x${VID}:0x${PID} already exists as {e['id']}!")
        sys.exit(1)

d["entries"].append(entry)

with open("Specs/quirks.json", "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"✅ Added {entry['id']} to quirks.json ({len(d['entries'])} total entries)")
print(f"📋 Don't forget to:")
print(f"   cp Specs/quirks.json SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json")
print(f"   swift test --filter QuirkMatchingTests")
PYEOF
