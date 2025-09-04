#!/usr/bin/env bash
set -euo pipefail

# SwiftMTP CLI Wrapper
# Usage: ./scripts/swiftmtp.sh <command> [args...]

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Navigate to the SwiftMTPKit directory
cd "$PROJECT_ROOT/SwiftMTPKit"

# Execute the swiftmtp command
exec swift run swiftmtp "$@"
