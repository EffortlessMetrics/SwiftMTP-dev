#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

echo "Running SwiftMTP Storybook (End-to-End Demo)..."

for profile in pixel7 galaxy iphone canon; do
    echo -e "\n>>> Testing Profile: $profile"
    export SWIFTMTP_MOCK_PROFILE=$profile
    swift run swiftmtp storybook
done

echo -e "\nEnd-to-End verification complete for all profiles."
