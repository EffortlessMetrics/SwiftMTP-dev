#!/usr/bin/env bash
set -euo pipefail

SPDX_HEADER="// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc."

echo "Adding SPDX headers to Swift files..."

# Find all .swift files and add header if not already present
find . -name "*.swift" -type f -print0 | while IFS= read -r -d '' file; do
    # Check if file already has SPDX header
    if ! head -2 "$file" | grep -q "SPDX-License-Identifier"; then
        echo "Adding SPDX header to: $file"
        # Create temp file with header + original content
        temp_file=$(mktemp)
        echo "$SPDX_HEADER" > "$temp_file"
        echo "" >> "$temp_file"
        cat "$file" >> "$temp_file"
        mv "$temp_file" "$file"
    else
        echo "SPDX header already present in: $file"
    fi
done

echo "SPDX header addition complete!"
