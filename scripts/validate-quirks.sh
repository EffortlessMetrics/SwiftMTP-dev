#!/bin/bash

# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.

set -e

echo "🔍 Validating Device Quirks Configuration"
echo "=========================================="

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "❌ jq is required for validation. Install with: brew install jq"
    exit 1
fi

QUIRKS_FILE="Specs/quirks.json"
SCHEMA_FILE="Specs/quirks.schema.json"

# Check that files exist
if [[ ! -f "$QUIRKS_FILE" ]]; then
    echo "❌ Quirks file not found: $QUIRKS_FILE"
    exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "❌ Schema file not found: $SCHEMA_FILE"
    exit 1
fi

echo "✅ Files found"

# Basic JSON validation
echo "🔍 Checking JSON syntax..."
if ! jq empty "$QUIRKS_FILE" >/dev/null 2>&1; then
    echo "❌ Invalid JSON in $QUIRKS_FILE"
    exit 1
fi

if ! jq empty "$SCHEMA_FILE" >/dev/null 2>&1; then
    echo "❌ Invalid JSON in $SCHEMA_FILE"
    exit 1
fi

echo "✅ JSON syntax is valid"

# Basic structure validation
echo "🔍 Checking quirks structure..."
version=$(jq -r '.version // empty' "$QUIRKS_FILE")
if [[ -z "$version" ]]; then
    echo "❌ Missing version field in quirks.json"
    exit 1
fi

if [[ "$version" -lt 1 ]]; then
    echo "❌ Invalid version: $version (must be >= 1)"
    exit 1
fi

entries_count=$(jq '.entries | length' "$QUIRKS_FILE")
if [[ "$entries_count" -eq 0 ]]; then
    echo "❌ No entries found in quirks.json"
    exit 1
fi

echo "✅ Found $entries_count quirk entries"

# Check that all referenced artifacts exist
echo "🔍 Checking artifact references..."
jq -r '.entries[].provenance.artifacts[]? // empty' "$QUIRKS_FILE" | while read -r artifact; do
    if [[ -n "$artifact" && "$artifact" != "null" ]]; then
        if [[ ! -f "$artifact" ]]; then
            echo "❌ Referenced artifact does not exist: $artifact"
            exit 1
        fi
    fi
done

echo "✅ All referenced artifacts exist"

# Ensure benchmark evidence is portable (no machine-specific absolute paths)
echo "🔍 Checking benchmark artifacts for absolute path leakage..."
if command -v rg >/dev/null 2>&1; then
    absolute_path_hits=$(rg -n --hidden -e '/Users/' -e '/home/' -e 'C:\\\\Users\\\\' Docs/benchmarks || true)
else
    absolute_path_hits=$(grep -RInE '/Users/|/home/|C:\\Users\\' Docs/benchmarks || true)
fi

if [[ -n "$absolute_path_hits" ]]; then
    echo "❌ Found absolute paths in Docs/benchmarks artifacts:"
    echo "$absolute_path_hits"
    exit 1
fi

echo "✅ Benchmark artifacts are portable"

# Validate entry IDs are unique
echo "🔍 Checking for duplicate entry IDs..."
ids=$(jq -r '.entries[].id' "$QUIRKS_FILE")
unique_ids=$(echo "$ids" | sort | uniq)
if [[ "$(echo "$ids" | wc -l)" != "$(echo "$unique_ids" | wc -l)" ]]; then
    echo "❌ Duplicate entry IDs found:"
    echo "$ids" | sort | uniq -d | while read -r dup; do
        echo "   DUPLICATE: $dup"
    done
    exit 1
fi

echo "✅ All entry IDs are unique"

# Validate VID+PID pairs are unique
echo "🔍 Checking for duplicate VID:PID pairs..."
vidpid_pairs=$(jq -r '.entries[] | "\(.match.vid):\(.match.pid)"' "$QUIRKS_FILE")
unique_pairs=$(echo "$vidpid_pairs" | sort | uniq)
if [[ "$(echo "$vidpid_pairs" | wc -l)" != "$(echo "$unique_pairs" | wc -l)" ]]; then
    echo "❌ Duplicate VID:PID pairs found:"
    echo "$vidpid_pairs" | sort | uniq -d | while read -r dup; do
        echo "   DUPLICATE VID:PID $dup used by:"
        jq -r --arg pair "$dup" '.entries[] | select("\(.match.vid):\(.match.pid)" == $pair) | "     \(.id)"' "$QUIRKS_FILE"
    done
    exit 1
fi

echo "✅ All VID:PID pairs are unique"

# Check that all entries have a governance status field
echo "🔍 Checking governance status field..."
missing_status=$(jq -r '.entries[] | select(.status == null) | .id' "$QUIRKS_FILE")
if [[ -n "$missing_status" ]]; then
    echo "❌ Entries missing 'status' field:"
    echo "$missing_status"
    exit 1
fi
echo "✅ All entries have a 'status' field"

# Warn (not fail) if any entry has status=proposed
proposed_count=$(jq '[.entries[] | select(.status == "proposed")] | length' "$QUIRKS_FILE")
if [[ "$proposed_count" -gt 0 ]]; then
    echo "⚠️  WARNING: $proposed_count entry/entries have status='proposed' (unverified — review before merging)"
    jq -r '.entries[] | select(.status == "proposed") | "   proposed: " + .id' "$QUIRKS_FILE"
fi

# Fail if a promoted profile is missing evidenceRequired
echo "🔍 Checking promoted profiles have evidenceRequired..."
missing_evidence=$(jq -r '.entries[] | select(.status == "promoted") | select(.evidenceRequired == null or (.evidenceRequired | length) == 0) | .id' "$QUIRKS_FILE")
if [[ -n "$missing_evidence" ]]; then
    echo "❌ Promoted profiles missing 'evidenceRequired':"
    echo "$missing_evidence"
    exit 1
fi
echo "✅ All promoted profiles have evidenceRequired"

# Validate bench gates against actual benchmark results
echo "🔍 Validating bench gates..."
jq -c '.entries[] | select(.benchGates) | {id: .id, readMin: (.benchGates.readMBpsMin // 0), writeMin: (.benchGates.writeMBpsMin // 0)}' "$QUIRKS_FILE" | while read -r entry; do
    id=$(echo "$entry" | jq -r '.id')
    read_min=$(echo "$entry" | jq -r '.readMin')
    write_min=$(echo "$entry" | jq -r '.writeMin')

    if [[ "$read_min" != "0" || "$write_min" != "0" ]]; then
        echo "  Checking gates for $id (read ≥ ${read_min} MB/s, write ≥ ${write_min} MB/s)..."

        # Look for benchmark CSV files for this device
        csv_files=$(find Docs/benchmarks/csv -name "${id//-/*}*.csv" 2>/dev/null | sort -r || true)

        if [[ -z "$csv_files" ]]; then
            echo "  ❌ No benchmark CSV found for $id"
            echo "    Required artifacts: Docs/benchmarks/csv/${id}-*.csv"
            if [[ "${CI:-false}" == "true" ]]; then
                echo "    CI requires benchmark evidence for quirk with gates"
                exit 1
            fi
        else
            # Use the most recent benchmark results
            latest_csv=$(echo "$csv_files" | head -1)
            echo "    Using benchmark file: $latest_csv"

            if [[ -f "$latest_csv" ]]; then
                # Extract read/write speeds from CSV with better parsing
                read_speed=$(grep -i "read" "$latest_csv" | tail -1 | sed 's/.*[,;]/ /' | grep -oE '[0-9]+\.?[0-9]*' | tail -1 || echo "0")
                write_speed=$(grep -i "write" "$latest_csv" | tail -1 | sed 's/.*[,;]/ /' | grep -oE '[0-9]+\.?[0-9]*' | tail -1 || echo "0")

                # Validate extracted values are numeric
                if ! [[ "$read_speed" =~ ^[0-9]*\.?[0-9]+$ ]]; then read_speed="0"; fi
                if ! [[ "$write_speed" =~ ^[0-9]*\.?[0-9]+$ ]]; then write_speed="0"; fi

                echo "    Measured: read=$read_speed MB/s, write=$write_speed MB/s"

                read_pass=$(awk "BEGIN {print ($read_speed >= $read_min) ? 1 : 0}")
                write_pass=$(awk "BEGIN {print ($write_speed >= $write_min) ? 1 : 0}")

                if [[ "$read_pass" -eq 1 ]]; then
                    echo "  ✅ Read gate passed: $read_speed ≥ $read_min MB/s"
                else
                    echo "  ❌ Read gate FAILED: $read_speed < $read_min MB/s"
                    if [[ "${CI:-false}" == "true" ]]; then
                        # Check for maintainer override
                        if [[ -n "${MAINTAINER_OVERRIDE:-}" ]]; then
                            echo "  ⚠️  MAINTAINER_OVERRIDE applied - allowing gate failure"
                            echo "    Reason: $MAINTAINER_OVERRIDE"
                        else
                            echo "  💡 Set MAINTAINER_OVERRIDE=reason to bypass gate in CI"
                            exit 1
                        fi
                    fi
                fi

                if [[ "$write_pass" -eq 1 ]]; then
                    echo "  ✅ Write gate passed: $write_speed ≥ $write_min MB/s"
                else
                    echo "  ❌ Write gate FAILED: $write_speed < $write_min MB/s"
                    if [[ "${CI:-false}" == "true" ]]; then
                        # Check for maintainer override
                        if [[ -n "${MAINTAINER_OVERRIDE:-}" ]]; then
                            echo "  ⚠️  MAINTAINER_OVERRIDE applied - allowing gate failure"
                            echo "    Reason: $MAINTAINER_OVERRIDE"
                        else
                            echo "  💡 Set MAINTAINER_OVERRIDE=reason to bypass gate in CI"
                            exit 1
                        fi
                    fi
                fi
            else
                echo "  ❌ Benchmark file not accessible: $latest_csv"
                if [[ "${CI:-false}" == "true" ]]; then
                    exit 1
                fi
            fi
        fi
    fi
done

echo "✅ Bench gates validation complete"

# Check that DocC generator source exists (built binary is 'swiftmtp-docs')
echo "🔍 Checking DocC generator..."
docc_generator_src="SwiftMTPKit/Sources/Tools/docc-generator-tool"
docc_generator_cmd="swift run --package-path SwiftMTPKit swiftmtp-docs"
if [[ ! -d "$docc_generator_src" ]]; then
    echo "❌ DocC generator source not found: $docc_generator_src"
    exit 1
fi

echo "✅ DocC generator source found (run via: $docc_generator_cmd)"

# Check DocC freshness (in CI mode)
if [[ "${CI:-false}" == "true" ]]; then
    echo "🔍 Checking DocC freshness..."

    # Generate docs and check if they differ from committed versions
    temp_dir=$(mktemp -d)
    echo "  Generating docs to $temp_dir..."

    if ! swift run --package-path SwiftMTPKit swiftmtp-docs "$QUIRKS_FILE" "$temp_dir" 2>/dev/null; then
        echo "❌ DocC generator failed to run"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Check if target directory exists
    if [[ ! -d "Docs/SwiftMTP.docc/Devices" ]]; then
        echo "❌ Target DocC directory does not exist: Docs/SwiftMTP.docc/Devices"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Compare generated docs with committed docs
    if ! diff -r "$temp_dir" "Docs/SwiftMTP.docc/Devices" >/dev/null 2>&1; then
        echo "❌ DocC files are stale!"
        echo "   Generated files differ from committed versions."
        echo ""
        echo "   To fix, regenerate docs:"
        echo "   swift run --package-path SwiftMTPKit swiftmtp-docs $QUIRKS_FILE Docs/SwiftMTP.docc/Devices"
        echo ""
        echo "   Then commit the changes."
        echo ""
        echo "   Diff summary:"
        diff -r "$temp_dir" "Docs/SwiftMTP.docc/Devices" | head -20
        rm -rf "$temp_dir"
        exit 1
    fi

    rm -rf "$temp_dir"
    echo "✅ DocC files are up to date"
fi

echo ""
echo "🎉 Validation complete!"
echo ""

if [[ "${CI:-false}" == "true" ]]; then
    echo "✅ All CI evidence gates passed!"
else
    echo "Next steps:"
    echo "1. Run DocC generator: swift run --package-path SwiftMTPKit swiftmtp-docs $QUIRKS_FILE Docs/SwiftMTP.docc/Devices"
    echo "2. Commit any generated documentation changes"
    echo "3. Test CLI commands: swift run swiftmtp quirks --explain"
    echo "4. Run benchmarks: ./scripts/benchmark-device.sh <device-id>"
    echo "5. For CI: Set CI=true to enable strict evidence validation"
fi

# ──────────────────────────────────────────────────────────
# JSON Schema validation (Python)
# ──────────────────────────────────────────────────────────
echo ""
echo "🔍 Running JSON Schema validation (Python)..."

python3 - "$QUIRKS_FILE" "$SCHEMA_FILE" << 'PYTHON_SCRIPT'
import json, re, sys

quirks_path = sys.argv[1]
schema_path = sys.argv[2]

with open(quirks_path) as f:
    data = json.load(f)
with open(schema_path) as f:
    schema = json.load(f)

errors = []
warnings = []

# Try jsonschema library first; fall back to manual checks
try:
    import jsonschema
    validator = jsonschema.Draft202012Validator(schema)
    schema_errors = sorted(validator.iter_errors(data), key=lambda e: list(e.absolute_path))
    for err in schema_errors:
        path = ".".join(str(p) for p in err.absolute_path) or "(root)"
        errors.append(f"Schema: {path}: {err.message}")
    if not schema_errors:
        print("  ✅ jsonschema validation passed")
except ImportError:
    print("  ⚠️  jsonschema not installed — running manual checks")

# ── Manual checks (always run, catch issues jsonschema might miss) ──

ID_RE = re.compile(r"^[a-z0-9-]+$")
VID_PID_RE = re.compile(r"^0x[0-9a-fA-F]{4}$")
VALID_STATUS = {"stable", "experimental", "proposed", "blocked", "promoted", "verified"}
VALID_CONFIDENCE = {"high", "medium", "low"}

seen_ids = set()
seen_vidpid = set()

for i, entry in enumerate(data.get("entries", [])):
    prefix = f"entries[{i}] ({entry.get('id', '?')})"

    # ID format and uniqueness
    eid = entry.get("id", "")
    if not ID_RE.match(eid):
        errors.append(f"{prefix}: id '{eid}' does not match ^[a-z0-9-]+$")
    if eid in seen_ids:
        errors.append(f"{prefix}: duplicate id '{eid}'")
    seen_ids.add(eid)

    # VID:PID format and uniqueness
    match = entry.get("match", {})
    vid = match.get("vid", "")
    pid = match.get("pid", "")
    if vid and not VID_PID_RE.match(vid):
        errors.append(f"{prefix}: match.vid '{vid}' does not match ^0x[0-9a-fA-F]{{4}}$")
    if pid and not VID_PID_RE.match(pid):
        errors.append(f"{prefix}: match.pid '{pid}' does not match ^0x[0-9a-fA-F]{{4}}$")
    pair = f"{vid}:{pid}"
    if pair in seen_vidpid:
        errors.append(f"{prefix}: duplicate VID:PID pair {pair}")
    seen_vidpid.add(pair)

    # ops — all values must be boolean
    ops = entry.get("ops", {})
    for k, v in ops.items():
        if not isinstance(v, bool):
            errors.append(f"{prefix}: ops.{k} is {type(v).__name__}, expected boolean")

    # flags — all values must be boolean (except preferredWriteFolder)
    flags = entry.get("flags", {})
    for k, v in flags.items():
        if k == "preferredWriteFolder":
            if not isinstance(v, str):
                errors.append(f"{prefix}: flags.preferredWriteFolder is {type(v).__name__}, expected string")
        elif not isinstance(v, bool):
            errors.append(f"{prefix}: flags.{k} is {type(v).__name__}, expected boolean")

    # evidenceRequired — must be array of strings
    evr = entry.get("evidenceRequired")
    if evr is not None:
        if not isinstance(evr, list):
            errors.append(f"{prefix}: evidenceRequired is {type(evr).__name__}, expected array")
        elif not all(isinstance(x, str) for x in evr):
            errors.append(f"{prefix}: evidenceRequired contains non-string elements")

    # status enum
    status = entry.get("status")
    if status and status not in VALID_STATUS:
        errors.append(f"{prefix}: status '{status}' not in {sorted(VALID_STATUS)}")

    # confidence enum
    conf = entry.get("confidence")
    if conf and conf not in VALID_CONFIDENCE:
        errors.append(f"{prefix}: confidence '{conf}' not in {sorted(VALID_CONFIDENCE)}")

    # governance.status enum
    gov = entry.get("governance", {})
    if isinstance(gov, dict):
        gs = gov.get("status")
        if gs and gs not in VALID_STATUS:
            errors.append(f"{prefix}: governance.status '{gs}' not in {sorted(VALID_STATUS)}")

if errors:
    print(f"\n  ❌ {len(errors)} validation error(s):")
    for e in errors[:25]:
        print(f"     {e}")
    if len(errors) > 25:
        print(f"     ... and {len(errors) - 25} more")
    sys.exit(1)
else:
    print("  ✅ All manual validation checks passed")
    print(f"     {len(seen_ids)} entries, {len(seen_vidpid)} unique VID:PID pairs")
PYTHON_SCRIPT

if [[ $? -ne 0 ]]; then
    echo "❌ JSON Schema validation failed"
    exit 1
fi

echo "✅ JSON Schema validation passed"
