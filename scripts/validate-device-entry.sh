#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <entry-id>"
    exit 1
fi

ENTRY_ID="$1"

python3 << PYEOF
import json, sys

with open("Specs/quirks.json") as f:
    d = json.load(f)

entry = None
for e in d["entries"]:
    if e["id"] == "$ENTRY_ID":
        entry = e
        break

if entry is None:
    print(f"❌ Entry '$ENTRY_ID' not found")
    sys.exit(1)

print(f"✅ Entry found: {entry['id']}")
print(f"   Device: {entry.get('deviceName', 'N/A')}")
print(f"   Category: {entry.get('category', 'unknown')}")
print(f"   VID:PID: {entry['match']['vid']}:{entry['match']['pid']}")
print(f"   Status: {entry.get('status', 'N/A')}")
print(f"   Confidence: {entry.get('confidence', 'N/A')}")

# Validate required fields
issues = []
if 'match' not in entry: issues.append("Missing 'match' field")
if 'vid' not in entry.get('match', {}): issues.append("Missing 'match.vid'")
if 'pid' not in entry.get('match', {}): issues.append("Missing 'match.pid'")
if not entry.get('category'): issues.append("Missing 'category'")
if not entry.get('status'): issues.append("Missing 'status'")
if isinstance(entry.get('hooks'), dict): issues.append("'hooks' should be array, not dict")

if issues:
    print(f"\n⚠️  Issues found:")
    for issue in issues:
        print(f"   - {issue}")
    sys.exit(1)
else:
    print(f"\n✅ All validations passed")
PYEOF
