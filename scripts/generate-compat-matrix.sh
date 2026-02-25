#!/bin/bash

# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.
#
# Reads Specs/quirks.json and prints a Markdown compatibility matrix to stdout.
# Usage: ./scripts/generate-compat-matrix.sh [quirks.json]

set -e

QUIRKS_FILE="${1:-Specs/quirks.json}"

if [[ ! -f "$QUIRKS_FILE" ]]; then
    echo "Error: Quirks file not found: $QUIRKS_FILE" >&2
    exit 1
fi

if command -v jq &>/dev/null; then
    echo "| Device | VID:PID | Status | Last Verified | Known Issues |"
    echo "| --- | --- | --- | --- | --- |"
    jq -r '
      .entries[] |
      (.id) as $id |
      ((.match.vid // "?") + ":" + (.match.pid // "?")) as $vidpid |
      (.status // "proposed") as $status |
      (.lastVerifiedDate // "—") as $date |
      (
        if (.behaviorLimitations // []) | length > 0 then
          .behaviorLimitations[0].description | gsub("\n";" ") |
          if length > 80 then .[0:80] + "…" else . end
        else "—" end
      ) as $issues |
      "| \($id) | \($vidpid) | \($status) | \($date) | \($issues) |"
    ' "$QUIRKS_FILE"
else
    python3 - "$QUIRKS_FILE" <<'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    data = json.load(f)

print("| Device | VID:PID | Status | Last Verified | Known Issues |")
print("| --- | --- | --- | --- | --- |")
for e in data.get("entries", []):
    did = e["id"]
    m = e.get("match", {})
    vidpid = "{}:{}".format(m.get("vid", "?"), m.get("pid", "?"))
    status = e.get("status", "proposed")
    date = e.get("lastVerifiedDate") or "—"
    lims = e.get("behaviorLimitations", [])
    if lims:
        desc = lims[0].get("description", "—").replace("\n", " ")
        issues = desc[:80] + "…" if len(desc) > 80 else desc
    else:
        issues = "—"
    print("| {} | {} | {} | {} | {} |".format(did, vidpid, status, date, issues))
PYEOF
fi
