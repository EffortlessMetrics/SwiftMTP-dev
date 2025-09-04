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

echo ""
echo "🎉 Validation complete!"
echo ""
echo "Next steps:"
echo "1. Run DocC generator: ./$docc_generator $QUIRKS_FILE Docs/SwiftMTP.docc/Devices"
echo "2. Commit any generated documentation changes"
echo "3. Test CLI commands: swift run swiftmtp quirks --explain"
