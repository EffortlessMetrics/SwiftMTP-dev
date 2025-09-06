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

# Validate entry IDs are unique
echo "🔍 Checking for duplicate entry IDs..."
ids=$(jq -r '.entries[].id' "$QUIRKS_FILE")
unique_ids=$(echo "$ids" | sort | uniq)
if [[ "$(echo "$ids" | wc -l)" != "$(echo "$unique_ids" | wc -l)" ]]; then
    echo "❌ Duplicate entry IDs found"
    exit 1
fi

echo "✅ All entry IDs are unique"

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

# Check that DocC generator exists and is executable
echo "🔍 Checking DocC generator..."
docc_generator="SwiftMTPKit/Sources/Tools/docc-generator"
if [[ ! -f "$docc_generator" ]]; then
    echo "❌ DocC generator not found: $docc_generator"
    exit 1
fi

if [[ ! -x "$docc_generator" ]]; then
    echo "⚠️  DocC generator is not executable, fixing..."
    chmod +x "$docc_generator"
fi

echo "✅ DocC generator is ready"

# Check DocC freshness (in CI mode)
if [[ "${CI:-false}" == "true" ]]; then
    echo "🔍 Checking DocC freshness..."

    if [[ ! -x "$docc_generator" ]]; then
        echo "❌ DocC generator not executable"
        exit 1
    fi

    # Generate docs and check if they differ from committed versions
    temp_dir=$(mktemp -d)
    echo "  Generating docs to $temp_dir..."

    if ! ./$docc_generator "$QUIRKS_FILE" "$temp_dir" 2>/dev/null; then
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
        echo "   ./$docc_generator $QUIRKS_FILE Docs/SwiftMTP.docc/Devices"
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
    echo "1. Run DocC generator: ./$docc_generator $QUIRKS_FILE Docs/SwiftMTP.docc/Devices"
    echo "2. Commit any generated documentation changes"
    echo "3. Test CLI commands: swift run swiftmtp quirks --explain"
    echo "4. Run benchmarks: ./scripts/benchmark-device.sh <device-id>"
    echo "5. For CI: Set CI=true to enable strict evidence validation"
fi
