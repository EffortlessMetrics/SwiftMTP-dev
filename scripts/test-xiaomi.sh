#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Xiaomi Mi Note 2 Diagnostic Test"
echo "=================================="

# Check if device is connected
echo "1. Checking USB device detection..."
if system_profiler SPUSBDataType | grep -q "Xiaomi"; then
    echo "✅ Xiaomi device detected by macOS"
    system_profiler SPUSBDataType | grep -A 10 "Xiaomi"
else
    echo "❌ Xiaomi device NOT detected by macOS"
    echo "   Please ensure the device is connected and unlocked"
    exit 1
fi

echo ""
echo "2. Checking USB permissions..."
if ls -la /dev/tty* 2>/dev/null | grep -q "crw"; then
    echo "✅ USB permissions look good"
else
    echo "⚠️  USB permissions may need checking"
fi

echo ""
echo "3. Checking for competing USB processes..."
COMPETING_PROCESSES=$(ps aux | grep -E "(usbmuxd|PTPCamera|Android)" | grep -v grep || true)
if [ -n "$COMPETING_PROCESSES" ]; then
    echo "⚠️  Found competing USB processes:"
    echo "$COMPETING_PROCESSES"
    echo ""
    echo "💡 Try killing these processes:"
    echo "   killall usbmuxd PTPCamera 2>/dev/null || true"
else
    echo "✅ No competing USB processes found"
fi

echo ""
echo "4. Testing SwiftMTP mock mode..."
if ./scripts/swiftmtp.sh --mock pixel7 probe > /dev/null 2>&1; then
    echo "✅ Mock mode working correctly"
else
    echo "❌ Mock mode failed"
    exit 1
fi

echo ""
echo "5. Device Setup Instructions:"
echo "   📱 On your Xiaomi Mi Note 2:"
echo "      1. Unlock the phone"
echo "      2. Go to Settings → Connected devices → USB"
echo "      3. Select 'File Transfer' (NOT 'Charging only')"
echo "      4. Make sure the phone screen is ON and unlocked"
echo ""
echo "6. Ready to test real device:"
echo "   ./scripts/swiftmtp.sh probe"
echo ""
echo "7. Alternative: Test with timeout (10 seconds):"
echo "   timeout 10 ./scripts/swiftmtp.sh probe || echo 'Command timed out - check device mode'"
