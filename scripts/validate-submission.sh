#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2025 Effortless Metrics, Inc.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SPECS_DIR="$REPO_ROOT/Specs"

# Check if a JSON schema validator is available
check_dependencies() {
    local has_validator=false

    # Check for Python with jsonschema
    if command -v python3 &> /dev/null; then
        if python3 -c "import jsonschema" &> /dev/null; then
            echo "✅ Found Python with jsonschema"
            has_validator=true
        fi
    fi

    # Check for Node.js with ajv-cli
    if command -v node &> /dev/null && command -v ajv &> /dev/null; then
        echo "✅ Found Node.js with ajv-cli"
        has_validator=true
    fi

    # Check for jq (for basic JSON validation)
    if command -v jq &> /dev/null; then
        echo "✅ Found jq for basic JSON validation"
    else
        echo "⚠️  jq not found - basic JSON validation will be limited"
    fi

    if [ "$has_validator" = false ]; then
        echo "⚠️  No JSON schema validator found. Install one of:"
        echo "   • Python: pip install jsonschema"
        echo "   • Node.js: npm install -g ajv-cli"
        echo "   Falling back to basic validation"
    fi
}

# Validate JSON against schema using available tools
validate_json_schema() {
    local json_file="$1"
    local schema_file="$2"
    local description="$3"

    echo "🔍 Validating $description..."

    # Basic JSON syntax validation
    if command -v jq &> /dev/null; then
        if ! jq empty "$json_file" &> /dev/null; then
            echo -e "${RED}❌ Invalid JSON syntax in $json_file${NC}"
            return 1
        fi
    else
        # Fallback: try to parse with Python
        if command -v python3 &> /dev/null; then
            if ! python3 -c "import json; json.load(open('$json_file'))" &> /dev/null; then
                echo -e "${RED}❌ Invalid JSON syntax in $json_file${NC}"
                return 1
            fi
        fi
    fi

    # Schema validation
    local schema_validated=false

    # Try Python with jsonschema
    if command -v python3 &> /dev/null; then
        if python3 -c "import jsonschema" &> /dev/null; then
            if python3 -c "
import json
import jsonschema
with open('$json_file') as f:
    data = json.load(f)
with open('$schema_file') as f:
    schema = json.load(f)
jsonschema.validate(data, schema)
" 2> /dev/null; then
                echo -e "${GREEN}✅ Schema validation passed for $description${NC}"
                schema_validated=true
            else
                echo -e "${RED}❌ Schema validation failed for $description${NC}"
                return 1
            fi
        fi
    fi

    # Try Node.js with ajv-cli (if Python failed)
    if [ "$schema_validated" = false ] && command -v node &> /dev/null && command -v ajv &> /dev/null; then
        if ajv validate -s "$schema_file" -d "$json_file" &> /dev/null; then
            echo -e "${GREEN}✅ Schema validation passed for $description${NC}"
            schema_validated=true
        else
            echo -e "${RED}❌ Schema validation failed for $description${NC}"
            return 1
        fi
    fi

    if [ "$schema_validated" = false ]; then
        echo -e "${YELLOW}⚠️  Schema validation skipped (no validator available)${NC}"
        echo -e "${YELLOW}   Basic JSON syntax is valid${NC}"
    fi

    return 0
}

# Validate submission manifest
validate_submission_manifest() {
    local manifest_file="$1"
    local schema_file="$SPECS_DIR/submission.schema.json"

    if [ ! -f "$schema_file" ]; then
        echo -e "${RED}❌ Submission schema not found: $schema_file${NC}"
        return 1
    fi

    validate_json_schema "$manifest_file" "$schema_file" "submission manifest"
}

# Validate quirk suggestion
validate_quirk_suggestion() {
    local quirk_file="$1"
    local schema_file="$SPECS_DIR/quirk-suggestion.schema.json"

    if [ ! -f "$schema_file" ]; then
        echo -e "${RED}❌ Quirk suggestion schema not found: $schema_file${NC}"
        return 1
    fi

    validate_json_schema "$quirk_file" "$schema_file" "quirk suggestion"
}

# Validate probe JSON
validate_probe_json() {
    local probe_file="$1"

    echo "🔍 Validating probe JSON structure..."

    if ! command -v jq &> /dev/null && ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}⚠️  Skipping probe validation (no JSON parser available)${NC}"
        return 0
    fi

    # Check for required fields
    local required_fields=("schemaVersion" "type" "timestamp" "fingerprint" "capabilities")
    for field in "${required_fields[@]}"; do
        if command -v jq &> /dev/null; then
            if ! jq -e ".${field}" "$probe_file" &> /dev/null; then
                echo -e "${RED}❌ Missing required field: $field${NC}"
                return 1
            fi
        elif command -v python3 &> /dev/null; then
            if ! python3 -c "
import json
data = json.load(open('$probe_file'))
if '$field' not in data:
    exit(1)
" 2> /dev/null; then
                echo -e "${RED}❌ Missing required field: $field${NC}"
                return 1
            fi
        fi
    done

    echo -e "${GREEN}✅ Probe JSON structure is valid${NC}"
}

# Validate benchmark CSV
validate_benchmark_csv() {
    local csv_file="$1"
    local size="$2"

    echo "🔍 Validating benchmark CSV ($size)..."

    # Check if file exists and is readable
    if [ ! -f "$csv_file" ]; then
        echo -e "${RED}❌ Benchmark file not found: $csv_file${NC}"
        return 1
    fi

    # Check CSV header
    local header
    header=$(head -1 "$csv_file")
    if [[ "$header" != "timestamp,operation,size_bytes,duration_seconds,speed_mbps" ]]; then
        echo -e "${RED}❌ Invalid CSV header in $csv_file${NC}"
        echo -e "${RED}   Expected: timestamp,operation,size_bytes,duration_seconds,speed_mbps${NC}"
        echo -e "${RED}   Found: $header${NC}"
        return 1
    fi

    # Check if file has data rows
    local line_count
    line_count=$(wc -l < "$csv_file")
    if [ "$line_count" -lt 2 ]; then
        echo -e "${RED}❌ Benchmark CSV has no data rows${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Benchmark CSV ($size) is valid${NC}"
}

# Validate privacy redaction in USB dump and other files
validate_privacy_redaction() {
    local usb_file="$1"

    echo "🔍 Validating privacy redaction..."

    # Check for unredacted serials in USB dump
    if grep -Eqi 'Serial Number:[[:space:]]*[A-Za-z0-9_-]+' "$usb_file"; then
        if ! grep -qi 'Serial Number: <redacted>' "$usb_file"; then
            echo -e "${RED}❌ USB dump contains unredacted serial numbers${NC}"
            return 1
        fi
    fi

    # Check for absolute user paths
    if grep -Eq '/Users/[^/[:space:]]+' "$usb_file"; then
        echo -e "${RED}❌ USB dump leaks local username paths${NC}"
        return 1
    fi

    # Check for Windows user paths
    if grep -Eqi 'C:\\Users\\[^\\[:space:]]+' "$usb_file"; then
        echo -e "${RED}❌ USB dump leaks Windows username paths${NC}"
        return 1
    fi

    # Check for Linux home paths
    if grep -Eqi '/home/[^/[:space:]]+' "$usb_file"; then
        echo -e "${RED}❌ USB dump leaks Linux username paths${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Privacy redaction validated${NC}"
}

# Extract and display summary information
display_summary() {
    local bundle_dir="$1"
    local manifest_file="$bundle_dir/submission.json"

    echo ""
    echo -e "${BLUE}📊 Submission Summary${NC}"
    echo -e "${BLUE}==================${NC}"

    if command -v jq &> /dev/null; then
        echo "Device: $(jq -r '.device.vendor + " " + .device.model' "$manifest_file")"
        echo "VID:PID: $(jq -r '.device.vendorId + ":" + .device.productId' "$manifest_file")"
        echo "Interface: $(jq -r '.device.interface.class + "/" + .device.interface.subclass + "/" + .device.interface.protocol' "$manifest_file")"
        echo "Collected at: $(jq -r '.timestamp' "$manifest_file")"
        echo "Benchmarks: $(jq -r '.artifacts.bench // empty | length' "$manifest_file") files"
    elif command -v python3 &> /dev/null; then
        python3 -c "
import json
with open('$manifest_file') as f:
    data = json.load(f)
print(f'Device: {data[\"device\"][\"vendor\"]} {data[\"device\"][\"model\"]}')
print(f'VID:PID: {data[\"device\"][\"vendorId\"]}:{data[\"device\"][\"productId\"]}')
print(f'Interface: {data[\"device\"][\"interface\"][\"class\"]}/{data[\"device\"][\"interface\"][\"subclass\"]}/{data[\"device\"][\"interface\"][\"protocol\"]}')
print(f'Collected at: {data[\"timestamp\"]}')
benches = data.get('artifacts', {}).get('bench', [])
print(f'Benchmarks: {len(benches) if benches else 0} files')
"
    fi
}

# Main validation function
validate_submission() {
    local bundle_dir="$1"

    echo -e "${BLUE}🔍 Validating SwiftMTP device submission${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo "Bundle: $bundle_dir"
    echo ""

    # Check if bundle directory exists
    if [ ! -d "$bundle_dir" ]; then
        echo -e "${RED}❌ Submission bundle directory not found: $bundle_dir${NC}"
        exit 1
    fi

    # Check for required files
    local manifest_file="$bundle_dir/submission.json"
    local probe_file="$bundle_dir/probe.json"
    local usb_dump_file="$bundle_dir/usb-dump.txt"
    local quirk_file="$bundle_dir/quirk-suggestion.json"
    local salt_file="$bundle_dir/.salt"

    local missing_files=()

    for file in "$manifest_file" "$probe_file" "$usb_dump_file" "$quirk_file"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required files:${NC}"
        for file in "${missing_files[@]}"; do
            echo -e "${RED}   • $(basename "$file")${NC}"
        done
        exit 1
    fi

    echo -e "${GREEN}✅ All required files present${NC}"

    # Validate manifest
    if ! validate_submission_manifest "$manifest_file"; then
        exit 1
    fi

    # Validate probe JSON
    if ! validate_probe_json "$probe_file"; then
        exit 1
    fi

    # Validate quirk suggestion
    if ! validate_quirk_suggestion "$quirk_file"; then
        exit 1
    fi

    # Validate benchmark files (if present)
    if command -v jq &> /dev/null; then
        local bench_files
        bench_files=$(jq -r '.artifacts.bench[]?' "$manifest_file" 2>/dev/null || echo "")
        for bench_file in $bench_files; do
            if [ -n "$bench_file" ]; then
                local full_path="$bundle_dir/$bench_file"
                local size
                size=$(echo "$bench_file" | sed -n 's/bench-\([0-9]*[KMG]\)\.csv/\1/p')
                if ! validate_benchmark_csv "$full_path" "$size"; then
                    exit 1
                fi
            fi
        done
    fi

    # Check salt file
    if [ ! -f "$salt_file" ]; then
        echo -e "${YELLOW}⚠️  Salt file not found (used for serial redaction)${NC}"
    else
        echo -e "${GREEN}✅ Salt file present for redaction${NC}"
    fi

    # Validate privacy redaction in USB dump
    validate_privacy_redaction "$usb_dump_file"

    display_summary "$bundle_dir"

    echo ""
    echo -e "${GREEN}🎉 Submission validation complete!${NC}"
    echo -e "${GREEN}   All checks passed. Ready for submission.${NC}"
}

# Print usage information
usage() {
    echo "SwiftMTP Submission Validator"
    echo ""
    echo "Usage: $0 <submission-bundle-directory>"
    echo ""
    echo "Validates a SwiftMTP device submission bundle created by 'swiftmtp collect'"
    echo ""
    echo "Arguments:"
    echo "  submission-bundle-directory  Path to the Contrib/submissions/<device>/ directory"
    echo ""
    echo "Example:"
    echo "  $0 Contrib/submissions/xiaomi-mi-note-2-2717-ff10-2025-09-03"
    echo ""
    echo "Dependencies:"
    echo "  • jq (recommended) or Python 3 for JSON parsing"
    echo "  • Python with jsonschema or Node.js with ajv-cli for schema validation"
    echo ""
    echo "Exit codes:"
    echo "  0 - Validation successful"
    echo "  1 - Validation failed"
    echo "  2 - Usage error"
}

# Main script logic
main() {
    if [ $# -ne 1 ]; then
        usage
        exit 2
    fi

    local bundle_dir="$1"

    # Convert to absolute path if relative
    if [[ "$bundle_dir" != /* ]]; then
        bundle_dir="$PWD/$bundle_dir"
    fi

    check_dependencies
    echo ""

    validate_submission "$bundle_dir"
}

# Run main function with all arguments
main "$@"
