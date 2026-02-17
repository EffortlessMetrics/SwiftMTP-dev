# How to Work with Device Quirks

This guide explains how to identify, configure, and apply device quirks in SwiftMTP to handle device-specific behaviors.

## What Are Device Quirks?

Device quirks are configuration settings that compensate for non-standard or buggy behavior in MTP devices. They allow SwiftMTP to work correctly with devices that don't follow the MTP specification exactly.

## Quick Start

If your device doesn't work correctly, try these common quirks:

```json
{
  "vid": "0x1234",
  "pid": "0x5678",
  "description": "My Device",
  "quirks": {
    "ioTimeoutMs": 30000,
    "maxChunkBytes": 2097152,
    "stabilizeMs": 1000
  }
}
```

## Identifying Quirk Requirements

### Symptoms That Indicate Quirk Needs

| Symptom | Likely Quirk |
|---------|-------------|
| Slow transfers | `maxChunkBytes` adjustment |
| Timeouts on session open | `handshakeTimeoutMs` |
| Intermittent failures | `stabilizeMs` |
| Write failures | Folder permissions quirk |
| Protocol errors | `resetOnOpen` |

### Profiling Your Device

```bash
# Run device profiling
swift run swiftmtp profile --vid 0x1234 --pid 0x5678

# This will suggest quirk values
```

The profiler tests various settings and recommends optimal values.

## Configuring Quirks

### Basic Quirk Options

```json
{
  "quirks": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 20000,
    "ioTimeoutMs": 30000,
    "stabilizeMs": 500,
    "resetOnOpen": false
  }
}
```

| Quirk | Type | Default | Description |
|-------|------|---------|-------------|
| `maxChunkBytes` | Int | 4194304 | Maximum transfer chunk size |
| `handshakeTimeoutMs` | Int | 10000 | Session open timeout |
| `ioTimeoutMs` | Int | 15000 | Transfer timeout |
| `stabilizeMs` | Int | 0 | Delay after session open |
| `resetOnOpen` | Bool | false | USB reset before session |

### Hooks

Hooks execute custom delays at specific phases:

```json
{
  "quirks": {
    "hooks": [
      {
        "phase": "postOpenSession",
        "delayMs": 500
      },
      {
        "phase": "preTransfer",
        "delayMs": 100
      }
    ]
  }
}
```

| Phase | Description |
|-------|-------------|
| `preOpenSession` | Before opening session |
| `postOpenSession` | After opening session |
| `preTransfer` | Before each transfer |
| `postTransfer` | After each transfer |
| `preCloseSession` | Before closing session |

## Applying Quirks

### Method 1: Environment Variables (Testing)

For quick testing:

```bash
# Test quirk values via environment
export SWIFTMTP_TEST_QUIRK_maxChunkBytes=2097152
export SWIFTMTP_TEST_QUIRK_ioTimeoutMs=30000
export SWIFTMTP_TEST_QUIRK_stabilizeMs=500

# Test your operations
swift run swiftmtp ls
```

### Method 2: Quirks Configuration File (Permanent)

Edit `Specs/quirks.json`:

```json
{
  "devices": [
    {
      "vid": "0x1234",
      "pid": "0x5678",
      "description": "My Device",
      "quirks": {
        "ioTimeoutMs": 30000,
        "maxChunkBytes": 2097152,
        "stabilizeMs": 500
      }
    }
  ]
}
```

### Validating Quirks

After editing quirks.json:

```bash
# Validate quirk configuration
swift run swiftmtp validate-quirks
```

## Common Quirk Patterns

### Slow Devices

Some devices need more time to process requests:

```json
{
  "vid": "0x1234",
  "pid": "0x5678",
  "quirks": {
    "handshakeTimeoutMs": 20000,
    "ioTimeoutMs": 45000,
    "stabilizeMs": 2000
  }
}
```

### Small Transfer Buffer

Devices with limited memory:

```json
{
  "quirks": {
    "maxChunkBytes": 524288,
    "ioTimeoutMs": 60000
  }
}
```

### USB Reset Issues

Devices that need a reset before use:

```json
{
  "quirks": {
    "resetOnOpen": true,
    "stabilizeMs": 1000
  }
}
```

### Write-Protected Folders

Some devices have restricted writable paths:

```json
{
  "quirks": {
    "writableFolders": [
      "/Download",
      "/Documents",
      "/Pictures/WhatsApp"
    ],
    "defaultFolder": "/Download"
  }
}
```

## Advanced Quirks

### Custom Device Properties

Access device-specific properties:

```json
{
  "quirks": {
    "properties": {
      "BatteryLevel": {
        "code": 0x5001,
        "type": "uint8"
      },
      "DeviceFriendlyName": {
        "code": 0x5002,
        "type": "string"
      }
    }
  }
}
```

### Protocol Workarounds

Handle protocol quirks:

```json
{
  "quirks": {
    "protocolWorkarounds": {
      "skipGetObjectProps": false,
      "useGetObjectInsteadOfGetPartial": true,
      "noDeleteAfterUpload": false
    }
  }
}
```

## Testing Quirks

### Automated Testing

```bash
# Run test with quirks
swift run swiftmtp test-quirks \
  --vid 0x1234 \
  --pid 0x5678 \
  --quirks '{"ioTimeoutMs":30000}'
```

### Manual Testing Checklist

1. ✅ Device discovery works
2. ✅ Session opens without timeout
3. ✅ File listing works
4. ✅ File download works
5. ✅ File upload works
6. ✅ Large file transfers complete
7. ✅ Multiple operations succeed
8. ✅ Disconnection/reconnection works

## Submitting Quirks

To contribute device quirks to SwiftMTP:

### 1. Gather Information

```bash
# Run comprehensive device lab
swift run swiftmtp device-lab connected --json > device-lab.json

# Profile the device
swift run swiftmtp profile --output profile.json
```

### 2. Create Submission

Submit a JSON file:

```json
{
  "submission": {
    "vid": "0x1234",
    "pid": "0x5678",
    "description": "Device Model Name",
    "manufacturer": "Manufacturer Name",
    "testedOperations": [
      "list",
      "download", 
      "upload",
      "delete"
    ],
    "quirks": {
      "ioTimeoutMs": 30000,
      "maxChunkBytes": 2097152
    },
    "notes": "Any additional notes about this device"
  }
}
```

### 3. Validate Submission

```bash
# Validate submission format
swift run swiftmtp validate-submission device-submission.json
```

See [Add Device Support](add-device-support.md) for full submission guidelines.

## Troubleshooting Quirk Issues

### Quirk Not Applied

```bash
# Check which quirks are active
swift run swiftmtp quirks --list

# Verify quirks.json is valid
swift run swiftmtp validate-quirks
```

### Quirk Causes New Issues

```bash
# Disable specific quirk via environment
export SWIFTMTP_DISABLE_QUIRK_stabilize=true

# Test without quirks
export SWIFTMTP_DISABLE_ALL_QUIRKS=true
swift run swiftmtp ls
```

## Reference

- [Device Quirks Explanation](../explanation/device-quirks.md)
- [Error Codes Reference](../reference/error-codes.md)
- [Add Device Support](add-device-support.md)

## Summary

You now know how to:

1. ✅ Identify when quirks are needed
2. ✅ Configure basic quirk options
3. ✅ Apply quirks via environment or config
4. ✅ Test quirks effectively
5. ✅ Submit quirks for contribution
6. ✅ Troubleshoot quirk issues