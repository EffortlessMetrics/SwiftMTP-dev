# SwiftMTP Benchmark Report
Device: oneplus-3t (ONEPLUS A3010)
Timestamp: Fri Feb  7 04:22:00 EST 2026
Mode: Real Device (USB Enumeration)

## Device Information
```
📱 Device Information:
   Manufacturer: OnePlus
   Model: ONEPLUS A3010
   Vendor ID: 0x2A70 (10864)
   Product ID: 0xF003 (61443)
   Serial Number: 5dfe2dc2
   USB Speed: SuperSpeed (USB 3.2 Gen 1)
```

## MTP Interface Configuration
```
Interface 0: MTP
   Class: 0x06 (Still Image)
   Subclass: 0x01
   Protocol: 0x01
   Input Endpoint: 0x81
   Output Endpoint: 0x01
   Event Endpoint: 0x82

Interface 1: Mass Storage
   Class: 0x08 (Mass Storage)
   Subclass: 0x06
   Protocol: 0x50
   Input Endpoint: 0x83
   Output Endpoint: 0x02
```

## USB Enumeration Status
✅ **Device detected via libusb USB enumeration**

⚠️ **MTP session establishment pending authorization**

The device is connected and visible to the system, but SwiftMTP cannot establish an MTP session. This requires:
1. Device unlock
2. "Trust this computer" acceptance on device
3. macOS USB privacy authorization

## Quirk Configuration
From `Specs/quirks.json`:
```json
{
  "id": "oneplus-3t-f003",
  "match": { "vid": "0x2a70", "pid": "0xf003" },
  "tuning": {
    "maxChunkBytes": 1048576,
    "handshakeTimeoutMs": 15000,
    "ioTimeoutMs": 30000,
    "inactivityTimeoutMs": 10000,
    "overallDeadlineMs": 120000,
    "stabilizeMs": 1000,
    "resetOnOpen": true
  },
  "hooks": [
    { "phase": "postOpenSession", "delayMs": 1000 }
  ],
  "confidence": "medium",
  "status": "experimental"
}
```

## Benchmark Results
### 100M Transfer
```
🏃 Benchmarking with 100.0 MB...
❌ Benchmark failed: transport(SwiftMTPCore.TransportError.noDevice)
```

### 500M Transfer
```
🏃 Benchmarking with 500.0 MB...
❌ Benchmark failed: transport(SwiftMTPCore.TransportError.noDevice)
```

### 1G Transfer
```
🏃 Benchmarking with 1.0 GB...
❌ Benchmark failed: transport(SwiftMTPCore.TransportError.noDevice)
```

## Resolution Steps
To complete real device benchmarks:
1. Unlock the OnePlus 3T device
2. Accept "Trust this computer" prompt if shown
3. Ensure macOS has granted USB access to terminal/VSCode
4. Re-run benchmark commands

## Files Generated
- `probe.txt` - USB enumeration data
- `bench-100m.txt` - 100MB benchmark attempt
- `bench-500m.txt` - 500MB benchmark attempt
- `bench-1g.txt` - 1GB benchmark attempt
- `mirror-test.txt` - Mirror test (pending)
