# Device Tuning Guide

@Metadata {
    @DisplayName("Device Tuning Guide")
    @PageKind(article)
    @Available(macOS, introduced: "26.0")
}

Comprehensive guide to device-specific tuning and quirks in SwiftMTP.

## Overview

SwiftMTP uses a **device quirks system** to handle variations in MTP implementations across different manufacturers and models. This system provides:

- **Automatic device detection** based on USB descriptors and device info
- **Performance tuning** parameters optimized for specific devices
- **Operation capability flags** for protocol variations
- **Evidence-based configuration** with benchmarks and provenance
- **Self-documenting behavior** through CLI tools

## How Device Matching Works

The system matches devices using a **precedence hierarchy** from most specific to least specific:

1. **Exact VID:PID + device info regex** (highest precedence)
2. **Exact VID:PID only**
3. **VID only**
4. **Device info regex only** (lowest precedence)
5. **Default settings** (fallback)

### Matching Criteria

Each device entry can specify:

- **USB Vendor/Product IDs** (hex format: `0x2717:0xff10`)
- **Device Info Pattern** (regex matching device description strings)
- **Interface Descriptors** (USB class/subclass/protocol)
- **Endpoint Addresses** (input/output/event endpoints)

## Tuning Parameters

Device-specific tuning parameters control:

### Performance Settings
- **Maximum Chunk Size**: Data transfer block size (131,072 - 16,777,216 bytes)
- **Handshake Timeout**: Initial connection timeout (1,000 - 60,000 ms)
- **I/O Timeout**: Individual operation timeout (1,000 - 60,000 ms)
- **Inactivity Timeout**: Connection idle timeout (1,000 - 60,000 ms)
- **Overall Deadline**: Total operation timeout (30,000 - 600,000 ms)

### Stability Settings
- **Stabilization Delay**: Post-session-open delay (0 - 2,000 ms)
- **Event Pump Delay**: Inter-event polling delay (0 - 5,000 ms)

## Operation Support Flags

Capability flags indicate device-specific protocol behaviors:

- **64-bit Partial Object Retrieval**: Device supports `GetPartialObject64`
- **Partial Object Sending**: Device supports `SendPartialObject`
- **Prefer Property List**: Use `GetObjectPropList` over `GetObjectPropsSupported`
- **Disable Write Resume**: Disable resumable write operations

## Benchmark Gates

Performance thresholds that must be met for device qualification:

- **Read Throughput Minimum**: Minimum MB/s for read operations
- **Write Throughput Minimum**: Minimum MB/s for write operations

## Adding a New Device

Follow this repeatable process:

### 1. Capture Evidence
```bash
# Probe device capabilities
swiftmtp probe --json > device-probe.json

# Capture USB topology
swiftmtp usb-dump > device-usb-dump.txt

# Run performance benchmarks
swiftmtp bench --size 100M --output device-100m.csv
swiftmtp bench --size 1G --output device-1g.csv

# Test mirror operation
swiftmtp mirror --log device-mirror.log
```

### 2. Draft Configuration
Create a new entry in `Specs/quirks.json`:

```json
{
  "id": "vendor-model-variant",
  "match": {
    "vid": "0xXXXX",
    "pid": "0xYYYY",
    "deviceInfoRegex": ".*Model Name.*"
  },
  "tuning": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 6000,
    "ioTimeoutMs": 15000,
    "inactivityTimeoutMs": 8000,
    "overallDeadlineMs": 120000
  }
}
```

### 3. Validate and Test
```bash
# Validate against schema
swift validate-json Specs/quirks.json Specs/quirks.schema.json

# Test with new device
swiftmtp quirks --explain
swiftmtp bench --size 100M
```

### 4. Commit Evidence
Save all artifacts in `Docs/benchmarks/` and update provenance in the JSON.

### 5. Generate Documentation
```bash
./Tools/docc-generator Specs/quirks.json
```

## CLI Self-Documentation

The CLI provides built-in explanation capabilities:

### Device Explanation
```bash
swiftmtp quirks --explain
```

Shows the matched quirk, active parameters, and performance gates.

### Device Fingerprinting
```bash
swiftmtp probe --json
```

Outputs machine-readable device information for creating new quirk entries.

## Status Levels

Device configurations have maturity levels:

- **Experimental**: Initial configuration, may need refinement
- **Stable**: Validated configuration with evidence
- **Deprecated**: No longer recommended, kept for reference

## Troubleshooting

### Common Issues

**Device not recognized**: Check USB dump output and update matching criteria.

**Performance below gates**: Adjust tuning parameters and re-benchmark.

**Protocol errors**: Verify operation support flags and USB interface details.

### Debug Information
```bash
# Verbose device detection
swiftmtp probe --verbose

# USB traffic analysis
swiftmtp usb-dump --filter vendor:0x2717
```

## Related Documentation

- [Benchmarks Overview](../benchmarks.md)
- [Troubleshooting Guide](../Troubleshooting.md)
- [File Provider Integration](../FileProvider-TechPreview.md)
