#!/usr/bin/env bash
set -euo pipefail

# submit-device.sh — End-to-end device submission helper for SwiftMTP.
# Collects device info, generates a quirk entry, validates it, and
# optionally creates a branch + PR.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUIRKS_FILE="$REPO_ROOT/Specs/quirks.json"
QUIRKS_COPY="$REPO_ROOT/SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json"

# ── Colour helpers ──────────────────────────────────────────────────
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

# ── Pre-flight checks ──────────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || { red "❌ python3 is required"; exit 1; }
command -v git     >/dev/null 2>&1 || { red "❌ git is required"; exit 1; }

if [ ! -f "$QUIRKS_FILE" ]; then
    red "❌ Cannot find $QUIRKS_FILE — run this script from the repo root"
    exit 1
fi

# ── Banner ──────────────────────────────────────────────────────────
echo ""
bold "📱 SwiftMTP Device Submission Wizard"
echo "===================================="
echo ""
echo "This script walks you through submitting a new MTP device to SwiftMTP."
echo "It will generate a quirk entry, validate it, and optionally open a PR."
echo ""

# ── Step 1: Collect device information ──────────────────────────────
bold "Step 1 of 4 — Device Information"
echo ""
echo "Tip: On macOS, find VID:PID in  → About This Mac → System Report → USB."
echo "     On Linux, run: lsusb"
echo ""

read -p "Vendor name (e.g., Samsung): " VENDOR
read -p "Device model (e.g., Galaxy S24): " DEVICE_NAME
read -p "Category (android / camera / media-player / dev-board / other): " CATEGORY

while true; do
    read -p "Vendor ID  — hex without 0x prefix (e.g., 04e8): " VID
    if [[ "$VID" =~ ^[0-9a-fA-F]{4}$ ]]; then break; fi
    yellow "⚠️  VID must be exactly 4 hex digits (e.g., 04e8)"
done

while true; do
    read -p "Product ID — hex without 0x prefix (e.g., 6860): " PID
    if [[ "$PID" =~ ^[0-9a-fA-F]{4}$ ]]; then break; fi
    yellow "⚠️  PID must be exactly 4 hex digits (e.g., 6860)"
done

# ── Step 2: Tuning defaults ────────────────────────────────────────
echo ""
bold "Step 2 of 4 — Tuning (press Enter for defaults)"
echo ""

read -p "Max chunk size in bytes [2097152]: " CHUNK_SIZE
CHUNK_SIZE=${CHUNK_SIZE:-2097152}
read -p "Handshake timeout in ms [5000]: " HANDSHAKE_TIMEOUT
HANDSHAKE_TIMEOUT=${HANDSHAKE_TIMEOUT:-5000}
read -p "I/O timeout in ms [10000]: " IO_TIMEOUT
IO_TIMEOUT=${IO_TIMEOUT:-10000}

# ── Step 3: Capability flags ───────────────────────────────────────
echo ""
bold "Step 3 of 4 — Capability flags"
echo ""

read -p "Supports GetPartialObject64? (y/n) [y]: " GET_PARTIAL
GET_PARTIAL=${GET_PARTIAL:-y}
read -p "Supports GetObjectPropList? (y/n) [y]: " GET_PROPLIST
GET_PROPLIST=${GET_PROPLIST:-y}

# ── Generate ID ─────────────────────────────────────────────────────
VID_LOWER=$(echo "$VID" | tr '[:upper:]' '[:lower:]')
PID_LOWER=$(echo "$PID" | tr '[:upper:]' '[:lower:]')
VENDOR_LOWER=$(echo "$VENDOR" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
DEVICE_LOWER=$(echo "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
ID="${VENDOR_LOWER}-${DEVICE_LOWER}-${PID_LOWER}"

GET_PARTIAL_BOOL=$( [[ "$GET_PARTIAL" == "y" ]] && echo "true" || echo "false" )
GET_PROPLIST_BOOL=$( [[ "$GET_PROPLIST" == "y" ]] && echo "true" || echo "false" )

echo ""
bold "Generated entry preview"
echo "  ID:      $ID"
echo "  VID:PID: 0x${VID_LOWER}:0x${PID_LOWER}"
echo "  Device:  $VENDOR $DEVICE_NAME"
echo ""

# ── Write entry to quirks.json ──────────────────────────────────────
python3 << PYEOF
import json, sys

entry = {
    "id": "$ID",
    "deviceName": "$VENDOR $DEVICE_NAME",
    "category": "$CATEGORY",
    "match": {"vid": "0x$VID_LOWER", "pid": "0x$PID_LOWER"},
    "tuning": {
        "maxChunkBytes": $CHUNK_SIZE,
        "handshakeTimeoutMs": $HANDSHAKE_TIMEOUT,
        "ioTimeoutMs": $IO_TIMEOUT
    },
    "hooks": [],
    "ops": {
        "supportsGetPartialObject64": $GET_PARTIAL_BOOL,
        "supportsGetObjectPropList": $GET_PROPLIST_BOOL
    },
    "flags": {},
    "status": "proposed",
    "confidence": "low",
    "source": "community",
    "evidenceRequired": ["probe-log"]
}

with open("$QUIRKS_FILE") as f:
    d = json.load(f)

for e in d["entries"]:
    if e["id"] == entry["id"]:
        print(f"❌ Entry with ID {entry['id']} already exists!")
        sys.exit(1)
    if e["match"].get("vid") == entry["match"]["vid"] and e["match"].get("pid") == entry["match"]["pid"]:
        print(f"❌ VID:PID 0x{entry['match']['vid']}:0x{entry['match']['pid']} already exists as {e['id']}!")
        sys.exit(1)

d["entries"].append(entry)

with open("$QUIRKS_FILE", "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"✅ Added {entry['id']} to Specs/quirks.json ({len(d['entries'])} total entries)")
PYEOF

# Sync to SwiftMTPQuirks resources
cp "$QUIRKS_FILE" "$QUIRKS_COPY"
green "✅ Synced quirks.json → SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/"

# ── Step 4: Validate ────────────────────────────────────────────────
echo ""
bold "Step 4 of 4 — Validation"
echo ""

VALIDATION_OK=true

if [ -x "$SCRIPT_DIR/validate-quirks.sh" ]; then
    echo "Running validate-quirks.sh …"
    if "$SCRIPT_DIR/validate-quirks.sh"; then
        green "✅ Quirks validation passed"
    else
        red "❌ Quirks validation failed — please fix issues above"
        VALIDATION_OK=false
    fi
else
    yellow "⚠️  validate-quirks.sh not found; skipping schema validation"
fi

if [ -x "$SCRIPT_DIR/validate-device-entry.sh" ]; then
    echo "Running validate-device-entry.sh $ID …"
    if "$SCRIPT_DIR/validate-device-entry.sh" "$ID"; then
        green "✅ Entry validation passed"
    else
        red "❌ Entry validation failed"
        VALIDATION_OK=false
    fi
fi

if [ "$VALIDATION_OK" != "true" ]; then
    red "⚠️  Validation issues detected. Fix them before submitting."
    echo "   You can re-run validation with:"
    echo "     ./scripts/validate-quirks.sh"
    echo "     ./scripts/validate-device-entry.sh $ID"
    exit 1
fi

# ── Optional: create branch & PR ────────────────────────────────────
echo ""
read -p "Create a git branch and open a PR now? (y/n) [n]: " CREATE_PR
CREATE_PR=${CREATE_PR:-n}

if [[ "$CREATE_PR" == "y" ]]; then
    BRANCH="device/${DEVICE_LOWER}-${PID_LOWER}"
    echo ""
    echo "Creating branch: $BRANCH"
    git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
    git add "$QUIRKS_FILE" "$QUIRKS_COPY"
    git commit -s -m "quirks: add $VENDOR $DEVICE_NAME ($ID)

Adds a community-proposed quirk entry for $VENDOR $DEVICE_NAME
(VID:PID 0x${VID_LOWER}:0x${PID_LOWER}).

Status: proposed | Confidence: low
Source: community submission via submit-device.sh"

    git push -u origin "$BRANCH"

    if command -v gh >/dev/null 2>&1; then
        gh pr create \
            --title "Device submission: $VENDOR $DEVICE_NAME (0x${VID_LOWER}:0x${PID_LOWER})" \
            --body "## New Device Submission

| Field | Value |
|-------|-------|
| **Device** | $VENDOR $DEVICE_NAME |
| **VID:PID** | \`0x${VID_LOWER}:0x${PID_LOWER}\` |
| **Category** | $CATEGORY |
| **Quirk ID** | \`$ID\` |
| **Status** | proposed |

Generated by \`scripts/submit-device.sh\`.

### Checklist
- [x] Entry added to \`Specs/quirks.json\`
- [x] Synced to \`SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json\`
- [x] Local validation passed
- [ ] Probe log attached (if available)
- [ ] Benchmarks attached (if available)" \
            --label "device-submission" \
            --base main
        green "✅ PR created!"
    else
        yellow "⚠️  gh CLI not found — push succeeded, open a PR manually on GitHub."
    fi
else
    echo ""
    green "🎉 Device entry created successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Review the entry:  jq '.entries[-1]' Specs/quirks.json"
    echo "  2. Run tests:         cd SwiftMTPKit && swift test --filter QuirkMatchingTests"
    echo "  3. Create a branch:   git checkout -b device/${DEVICE_LOWER}-${PID_LOWER}"
    echo "  4. Commit & push:     git add -A && git commit -s -m 'quirks: add $ID'"
    echo "  5. Open a PR on GitHub with your probe logs and benchmarks"
    echo ""
    echo "Or re-run this script with the PR option to automate steps 3-5."
fi
