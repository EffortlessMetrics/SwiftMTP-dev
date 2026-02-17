# How to Add Device Support

This guide explains how to add support for a new MTP device to SwiftMTP.

## Overview

Adding device support involves:
1. Capturing device information (probe)
2. Testing operations
3. Identifying quirks
4. Submitting quirks to the database

## Prerequisites

- SwiftMTP installed
- Device connected
- GitHub account (for contributions)

## Step 1: Capture Device Information

### Run Probe

```bash
# Capture basic device info
swift run swiftmtp probe > my-device-probe.txt
```

### Run Full Diagnostics

```bash
# Capture comprehensive device data
swift run swiftmtp device-lab connected --json

# Or use device bring-up script
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x1234 --pid 0x5678
```

### Collect Evidence Bundle

```bash
# Create submission-ready bundle
swift run swiftmtp collect --strict --noninteractive \
  --bundle ../Contrib/submissions/my-device-bundle
```

This creates a bundle with:
- Probe data
- USB dump
- Device properties
- Operation receipts

## Step 2: Test Operations

### Verify Each Operation

| Operation | Test Command |
|-----------|--------------|
| Enumerate | `swiftmtp ls` |
| Read | `swiftmtp pull /file.jpg` |
| Write | `swiftmtp push test.txt --to /Download` |
| Delete | `swiftmtp rm /Download/test.txt` |

### Record Results

Document any failures or workarounds:
- Error codes
- Required retries
- Special folders needed

## Step 3: Identify Quirks

### Common Quirk Patterns

```json
{
  "vid": "0x1234",
  "pid": "0x5678",
  "description": "My Device",
  "quirks": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 10000,
    "ioTimeoutMs": 20000,
    "stabilizeMs": 500,
    "hooks": [
      { "phase": "postOpenSession", "delayMs": 500 }
    ]
  }
}
```

### Quirk Reference

| Quirk | Description | Typical Values |
|-------|-------------|-----------------|
| `maxChunkBytes` | Transfer chunk size | 1-16 MB |
| `handshakeTimeoutMs` | OpenSession timeout | 5000-30000 |
| `ioTimeoutMs` | Transfer timeout | 10000-60000 |
| `stabilizeMs` | Post-open delay | 200-2000 |
| `resetOnOpen` | Reset device on open | true/false |

### Hooks

| Hook | Description |
|------|-------------|
| `postOpenSession` | Delay after opening session |
| `preGetStorageIDs` | Delay before storage enumeration |
| `busyBackoff` | Retry strategy for DEVICE_BUSY |

## Step 4: Add Device to Quirks Database

### Edit quirks.json

```bash
# Add your device to Specs/quirks.json
vim Specs/quirks.json
```

### Validate Quirks

```bash
# Verify JSON is valid
swift run swiftmtp validate-quirks

# Check your device specifically
swift run swiftmtp quirks --vid 0x1234 --pid 0x5678
```

## Step 5: Submit Contribution

### Create Submission Bundle

```bash
# Finalize submission bundle
swift run swiftmtp collect --strict --noninteractive \
  --bundle ../Contrib/submissions/my-device-bundle
```

### Submit Pull Request

1. Fork the repository
2. Add device to `Specs/quirks.json`
3. Add device documentation to `Docs/SwiftMTP.docc/Devices/`
4. Include benchmark results if available
5. Submit PR with:
   - Device name and VID:PID
   - Description of tested operations
   - Quirks applied
   - Any limitations

## Device Documentation Template

```markdown
# Device Name (VID:PID)

## Summary
- Status: ✅ Working / ⚠️ Partial / ❌ Blocked
- Host: macOS <version>
- SwiftMTP: <version>

## Modes
| Mode | Enumerates | Handshake | Read | Write |
|------|------------|-----------|------|-------|
| MTP Unlocked | ✅ | ✅ | ✅ | ✅ |

## Known Quirks
- `stabilizeMs`: 500
- `maxChunkBytes`: 2097152

## Evidence
- `Docs/benchmarks/device-bringup/<timestamp>/`
```

## Troubleshooting

### Device Not Detected

- Check USB mode is MTP
- Try different cable/port
- Disable USB debugging

### Operations Fail

- Try longer timeouts
- Add stabilization delay
- Check for folder restrictions

### Write Fails

- Try /Download folder
- Check if device is locked
- Verify USB mode is MTP not PTP

## Related Documentation

- [Device Bring-Up Guide](../../device-bringup.md)
- [Benchmarks Guide](run-benchmarks.md)
- [Device Tuning Guide](../reference/../SwiftMTP.docc/DeviceTuningGuide.md)

## Summary

You now know how to:
1. ✅ Capture device information
2. ✅ Test operations
3. ✅ Identify quirks
4. ✅ Add device to quirks database
5. ✅ Submit contribution
