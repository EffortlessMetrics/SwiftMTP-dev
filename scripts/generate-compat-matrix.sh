#!/usr/bin/env bash
set -euo pipefail
# Auto-generate Docs/compat-matrix.md from Specs/quirks.json
# Usage: ./scripts/generate-compat-matrix.sh

# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUIRKS_FILE="$REPO_ROOT/Specs/quirks.json"
OUTPUT_FILE="$REPO_ROOT/Docs/compat-matrix.md"

if [[ ! -f "$QUIRKS_FILE" ]]; then
    echo "Error: Quirks file not found: $QUIRKS_FILE" >&2
    exit 1
fi

python3 - "$QUIRKS_FILE" "$OUTPUT_FILE" <<'PYEOF'
import json, sys, re

quirks_path, output_path = sys.argv[1], sys.argv[2]
with open(quirks_path) as f:
    data = json.load(f)

STATUS_EMOJI = {"promoted": "✅", "verified": "✓", "proposed": "⚪"}

def device_name(entry_id):
    # Strip trailing -<pid> segment (hex suffix) and title-case
    name = re.sub(r'-[0-9a-f]{4}$', '', entry_id)
    return ' '.join(w.upper() if w in ('mtp', 'dslr', 'eos', 'usb') else w.capitalize()
                    for w in name.split('-'))

def format_vidpid(vid, pid):
    # Strip 0x prefix only (preserve leading zeros)
    def strip_0x(s):
        return s[2:] if s and s.lower().startswith('0x') else s
    v = strip_0x(vid) if vid and vid != '?' else '?'
    p = strip_0x(pid) if pid and pid != '?' else '?'
    return f"{v}:{p}"

def format_status(status):
    emoji = STATUS_EMOJI.get(status, "")
    return f"{emoji} {status}" if emoji else status

def format_quirks(ops):
    return ', '.join(k for k, v in ops.items() if v is True) or '—'

entries = data.get("entries", [])
lines = [
    "# Compatibility Matrix",
    "",
    "Auto-generated from Specs/quirks.json — do not edit manually.",
    "",
    "| Device | VID:PID | Status | Quirks |",
    "|--------|---------|--------|--------|",
]
for e in entries:
    m = e.get("match", {})
    name = device_name(e["id"])
    vidpid = format_vidpid(m.get("vid", "?"), m.get("pid", "?"))
    status = format_status(e.get("status", "proposed"))
    quirks = format_quirks(e.get("ops", {}))
    lines.append(f"| {name} | {vidpid} | {status} | {quirks} |")

with open(output_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"Generated {output_path} with {len(entries)} entries")
PYEOF
