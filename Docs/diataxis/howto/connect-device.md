# How to Connect a New Device

This guide shows you how to connect and configure a new MTP device with SwiftMTP.

## Quick Steps

1. Prepare your device (enable MTP mode)
2. Connect via USB
3. Run device probe
4. Verify connection
5. Configure quirks (if needed)

## Step 1: Prepare Your Device

### Android Devices

1. **Enable Developer Options**: Settings > About Phone > Build Number (tap 7 times)
2. **Enable USB Debugging**: Settings > Developer Options > USB Debugging (disable for MTP)
3. **Set USB Mode**: Settings > Storage > USB Computer Connection > **File Transfer (MTP)**

### iOS Devices

iOS doesn't natively support MTP. Use alternative methods:
- Files app with external drive support
- Image Capture app
- Third-party apps like iMazing

### Cameras

1. Set USB mode to **PTP** or **MTP**
2. Some cameras require PC Control mode

## Step 2: Connect the Device

```bash
# Connect device and run probe
swift run swiftmtp probe
```

Expected output for a new device:

```
[INFO] Scanning for MTP devices...
[INFO] Found device: Device Name (1234:5678)
[INFO] Manufacturer: ManufacturerName
[INFO] Model: ModelName
[INFO] Serial: <redacted>
```

## Step 3: Verify Connection

### List Files

```bash
swift run swiftmtp ls
```

### Get Device Info

```bash
swift run swiftmtp device-info
```

Shows:
- Device properties
- Supported operations
- Storage info

## Step 4: Test Operations

### Read Test

```bash
# Try to list files
swift run swiftmtp ls /Download
```

### Write Test

```bash
# Try to create a test file
echo "test" | swift run swiftmtp push --to /Download --name test.txt
```

## Step 5: Device Quirks (If Needed)

If the device doesn't work correctly, you may need quirks.

### Check Existing Quirks

```bash
swift run swiftmtp quirks --explain
```

### Common Quirk Configurations

```json
{
  "vid": "0x1234",
  "pid": "0x5678",
  "description": "My Device",
  "quirks": {
    "maxChunkBytes": 1048576,
    "handshakeTimeoutMs": 10000,
    "ioTimeoutMs": 20000,
    "stabilizeMs": 500,
    "hooks": [
      { "phase": "postOpenSession", "delayMs": 500 }
    ]
  }
}
```

### Applying Quirks

Edit `Specs/quirks.json` to add device-specific settings:

```bash
# Validate quirks after editing
swift run swiftmtp validate-quirks
```

## Device-Specific Guides

See these guides for known device configurations:

- [Google Pixel 7](../SwiftMTP.docc/Devices/google-pixel-7-4ee1.md)
- [OnePlus 3T](../SwiftMTP.docc/Devices/oneplus-3t-f003.md)
- [Xiaomi Mi Note 2](../SwiftMTP.docc/Devices/xiaomi-mi-note-2-ff10.md)
- [Samsung Galaxy](../SwiftMTP.docc/Devices/samsung-android-6860.md)

## Troubleshooting

If connection fails:

1. **Check USB mode** - Must be "File Transfer (MTP)"
2. **Try different cable** - Avoid charge-only cables
3. **Try different port** - Direct port, not hub
4. **Unlock screen** - Keep device unlocked
5. **Accept trust prompt** - Tap "Trust This Computer"

See [Troubleshoot Connection Issues](troubleshoot-connection.md) for more help.

## Next Steps

- 📊 [Run Benchmarks](run-benchmarks.md) - Test device performance
- 📋 [Transfer Files](transfer-files.md) - Detailed transfer operations
- 📋 [Device Quirks](device-quirks.md) - Configure device quirks
- 📋 [Add Device Support](add-device-support.md) - Contribute device quirks
- 📖 [Error Codes](../reference/error-codes.md) - Understand error messages
- 📖 [Configuration](../reference/configuration.md) - Configuration options

## Summary

You now know how to:
1. ✅ Prepare a device for MTP connection
2. ✅ Connect and probe the device
3. ✅ Test basic operations
4. ✅ Configure device quirks if needed
