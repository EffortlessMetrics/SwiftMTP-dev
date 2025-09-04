#!/usr/bin/env bash
set -euo pipefail

LICENSOR="Effortless Metrics, Inc."
LAW="Delaware"
VENUE="New York, NY"
LICENSING_EMAIL="licensing@effortlessmetrics.com"
SECURITY_EMAIL="security@effortlessmetrics.com"
SUPPORT_EMAIL="support@effortlessmetrics.com"

# macOS sed in-place (-i '') variant
find legal -type f -name "*.md" -print0 | xargs -0 sed -i '' \
  -e "s/<<LICENSOR>>/${LICENSOR//\//\\/}/g" \
  -e "s/<<GOVERNING_LAW>>/${LAW}/g" \
  -e "s/<<VENUE>>/${VENUE}/g" \
  -e "s/<<LICENSING_EMAIL>>/${LICENSING_EMAIL}/g" \
  -e "s/<<SECURITY_EMAIL>>/${SECURITY_EMAIL}/g" \
  -e "s/<<SUPPORT_EMAIL>>/${SUPPORT_EMAIL}/g"

echo "Legal templates filled with:"
echo "  Licensor: $LICENSOR"
echo "  Governing Law: $LAW"
echo "  Venue: $VENUE"
echo "  Licensing Email: $LICENSING_EMAIL"
echo "  Security Email: $SECURITY_EMAIL"
echo "  Support Email: $SUPPORT_EMAIL"
