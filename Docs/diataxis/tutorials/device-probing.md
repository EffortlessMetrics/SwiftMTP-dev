# Device Probing and Analysis

This tutorial teaches you how to probe, analyze, and understand a new MTP device using SwiftMTP's diagnostic tools.

## What You'll Learn

- Run device probes to discover device capabilities
- Analyze device properties and storage information
- Identify device-specific quirks and limitations
- Generate diagnostic reports for troubleshooting

## Prerequisites

- Completed [Getting Started](tutorials/getting-started.md)
- A new or unknown MTP device to analyze
- SwiftMTP installed (see [Installation](tutorials/getting-started.md#step-1-install-swiftmtp))

## Step 1: Basic Device Discovery

The first step in analyzing any device is to discover what MTP devices are connected.

### Running a Probe

```bash
swift run swiftmtp probe
```

Expected output for a connected device:

```
[INFO] Scanning for MTP devices...
[INFO] Found device: Google Pixel 7 (18d1:4ee1)
[INFO] Manufacturer: Google
[INFO] Model: Pixel 7
[INFO] Serial: <redacted>
```

### Verbose Probe Output

For detailed information about the device:

```bash
swift run swiftmtp probe --verbose
```

This reveals:
- USB vendor ID (VID) and product ID (PID)
- Device serial number
- Supported MTP operations
- Protocol version

## Step 2: Device Information Retrieval

Once a device is discovered, get comprehensive information about its capabilities.

### Get Full Device Info

```bash
swift run swiftmtp device-info
```

This command outputs:

```
Device Information:
├── Vendor ID: 0x18d1
├── Product ID: 0x4ee1
├── Manufacturer: Google
├── Model: Pixel 7
├── Serial: <redacted>
├── MTP Version: 1.0
├── Protocol Version: 100
└── Operations Supported:
    ├── OpenSession
    ├── CloseSession
    ├── GetDeviceInfo
    ├── GetStorageIDs
    ├── GetObjectHandles
    ├── GetObjectInfo
    ├── GetObject
    ├── SendObjectInfo
    ├── SendObject
    └── ...
```

### Storage Information

List all storage volumes on the device:

```bash
swift run swiftmtp ls
```

Output shows storage structure:

```
Storage: Primary (0)
├── DCIM/
│   └── Camera/
├── Download/
├── Pictures/
│   ├── Screenshots/
│   └── WhatsApp/
└── Movies/

Storage: SD Card (1)
├── ...
```

## Step 3: Analyzing Device Capabilities

Understanding what operations a device supports is crucial for proper interaction.

### Check Supported Operations

```bash
# Use device-lab for comprehensive diagnostics
swift run swiftmtp device-lab connected --json
```

This JSON output includes:

```json
{
  "device": {
    "vendorId": "0x18d1",
    "productId": "0x4ee1",
    "manufacturer": "Google",
    "model": "Pixel 7"
  },
  "capabilities": {
    "operations": [
      "OpenSession",
      "CloseSession", 
      "GetDeviceInfo",
      "GetStorageIDs",
      "GetObjectHandles",
      "GetObjectInfo",
      "GetObject",
      "SendObjectInfo",
      "SendObject",
      "DeleteObject"
    ],
    "formats": [
      "Undefined",
      "Directory",
      "EXIF/JPEG",
      "PNG",
      "MP3",
      "MP4"
    ]
  }
}
```

### Key Capabilities to Check

| Capability | Meaning |
|------------|---------|
| `GetPartialObject64` | Supports resume for large downloads |
| `SendPartialObject` | Supports resume for uploads |
| `DeleteObject` | Can delete files |
| `MoveObject` | Can move/rename files |
| `CopyObject` | Can copy files |

## Step 4: Device Profiling for Quirks

If a device doesn't work correctly, you need to gather profiling data.

### Generate Profiling Report

```bash
# Run comprehensive profiling
swift run swiftmtp profile --output device-profile.json
```

### Profiling Process

The profiling tool performs:

1. **Connection Timing**
   - Time to enumerate device
   - Session open/close latency
   - Operation response times

2. **Transfer Testing**
   - Small file transfer (1 KB)
   - Medium file transfer (1 MB)
   - Large file transfer (100 MB)
   - Tests for chunking behavior

3. **Stress Testing**
   - Rapid sequential operations
   - Concurrent operation handling
   - Error recovery

### Analyze Results

The profile report includes:

```json
{
  "timing": {
    "openSession": 245,
    "getStorageIds": 12,
    "listRoot": 89
  },
  "transfer": {
    "smallFile": {
      "size": 1024,
      "duration": 156,
      "speedKBps": 6.5
    },
    "largeFile": {
      "size": 104857600,
      "duration": 45234,
      "speedKBps": 2318
    }
  },
  "quirks": {
    "suggested": {
      "ioTimeoutMs": 30000,
      "maxChunkBytes": 2097152,
      "stabilizeMs": 1000
    }
  }
}
```

## Step 5: USB Layer Analysis

For deep troubleshooting, analyze USB-level communication.

### USB Traffic Capture

```bash
# Capture USB events
swift run swiftmtp usb-dump --output usb-capture.txt
```

This captures:
- USB device enumeration
- Interface selection
- Endpoint configuration
- Control transfers
- Bulk transfers

### Understanding USB Errors

Common USB-level errors:

| Error | Meaning |
|-------|---------|
| `LIBUSB_ERROR_NOT_FOUND` | Device disconnected |
| `LIBUSB_ERROR_NO_DEVICE` | Device detached |
| `LIBUSB_ERROR_ACCESS` | Permission denied |
| `LIBUSB_ERROR_TIMEOUT` | Operation timed out |
| `LIBUSB_ERROR_PIPE` | Endpoint stalled |

## Step 6: Automated Device Bring-Up

For new devices, use the automated bring-up script:

```bash
# Full device analysis
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x1234 --pid 0x5678
```

This script:
1. Probes the device repeatedly
2. Tests all basic operations
3. Captures full diagnostic output
4. Generates a report for analysis

## Understanding Device States

During probing, devices transition through states:

```
Discovered → Enumerating → Ready → (Error)
                ↓
            Connected
                ↓
            Authorized
                ↓
             Sessions
```

| State | Description |
|-------|-------------|
| `Discovered` | USB device found |
| `Enumerating` | Reading device info |
| `Connected` | MTP session opened |
| `Authorized` | User approved connection |
| `Ready` | Operations available |
| `Error` | Problem occurred |

## Troubleshooting Probing Issues

### Device Not Found

If probe returns "No MTP device connected":

1. **Check USB mode**: Must be MTP, not PTP
2. **Try different cable**: Use data-capable cable
3. **Direct connection**: Connect directly to Mac
4. **Check permissions**: Accept trust prompt

### Partial Information

If some information is missing:

```bash
# Run with maximum verbosity
swift run swiftmtp probe --verbose 2>&1 | tee probe-log.txt
```

This helps identify where in the process issues occur.

## Next Steps

- 📋 [Debugging MTP Issues](debugging-mtp.md) - Debug problems
- 📋 [Connect Device](../howto/connect-device.md) - Connect a new device
- 📋 [Device Quirks](../howto/device-quirks.md) - Configure quirks
- 📋 [Run Benchmarks](../howto/run-benchmarks.md) - Test performance

## Summary

In this tutorial, you learned how to:

1. ✅ Run basic device probes
2. ✅ Retrieve comprehensive device information
3. ✅ Analyze device capabilities
4. ✅ Profile device performance
5. ✅ Capture USB-level diagnostics
6. ✅ Use automated bring-up tools

This knowledge is essential for troubleshooting and adding support for new devices.