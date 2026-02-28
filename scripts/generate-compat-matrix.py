#!/usr/bin/env python3
"""Regenerate Docs/compat-matrix.md from Specs/quirks.json."""
import json

with open("Specs/quirks.json") as f:
    d = json.load(f)

entries = d["entries"]
by_category = {}
for e in entries:
    cat = e.get("category", "unknown")
    by_category.setdefault(cat, []).append(e)

vids = set()
for e in entries:
    vids.add(e["match"]["vid"])

with open("Docs/compat-matrix.md", "w") as f:
    f.write("# Compatibility Matrix\n\n")
    f.write("Auto-generated from Specs/quirks.json — do not edit manually.\n\n")
    f.write(f"**{len(entries):,}** device entries across **{len(vids)}** vendor IDs and **{len(by_category)}** categories.\n\n")

    for cat in sorted(by_category.keys()):
        cat_entries = by_category[cat]
        f.write(f"## {cat.replace('-', ' ').title()} ({len(cat_entries)})\n\n")
        f.write("| Device | VID:PID | Status | Confidence |\n")
        f.write("|--------|---------|--------|------------|\n")
        for e in sorted(cat_entries, key=lambda x: x.get("deviceName", "")):
            name = e.get("deviceName", e["id"])
            vid = e["match"]["vid"]
            pid = e["match"]["pid"]
            status = e.get("status", "unknown")
            confidence = e.get("confidence", "unknown")
            f.write(f"| {name} | {vid}:{pid} | {status} | {confidence} |\n")
        f.write("\n")

print(f"Generated compat-matrix.md: {len(entries)} entries, {len(vids)} VIDs, {len(by_category)} categories")
