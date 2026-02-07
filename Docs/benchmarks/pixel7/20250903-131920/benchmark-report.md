# SwiftMTP Benchmark Report
Device: pixel7 (google-pixel-7-4ee1)
Timestamp: Fri Feb  7 04:22:00 EST 2026
Mode: Real Device (USB Enumeration)

## Device Information
```
📱 Device Information:
   Manufacturer: Google
   Model: Pixel 7
   Vendor ID: 0x18D1 (6353)
   Product ID: 0x4EE1 (20193)
   Serial Number: 2A221FDH200G2Q
   USB Speed: SuperSpeed (USB 3.2 Gen 1)
```

## MTP Interface Configuration
```
Interface: MTP
   Class: 0x06 (Still Image)
   Subclass: 0x01
   Protocol: 0x01
   Input Endpoint: 0x81
   Output Endpoint: 0x01
   Event Endpoint: 0x82
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
  "id": "google-pixel-7-4ee1",
  "match": { "vid": "0x18d1", "pid": "0x4ee1" },
  "tuning": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 20000,
    "ioTimeoutMs": 30000,
    "inactivityTimeoutMs": 10000,
    "overallDeadlineMs": 180000,
    "stabilizeMs": 2000,
    "resetOnOpen": false
  },
  "confidence": "medium",
  "status": "stable"
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
1. Unlock the Pixel 7 device
2. Accept "Trust this computer" prompt if shown
3. Ensure macOS has granted USB access to terminal/VSCode
4. Re-run benchmark commands

## Files Generated
- `probe.txt` - USB enumeration data
- `bench-100m.txt` - 100MB benchmark attempt
- `bench-500m.txt` - 500MB benchmark attempt
- `bench-1g.txt` - 1GB benchmark attempt
- `mirror-test.txt` - Mirror test (pending)
