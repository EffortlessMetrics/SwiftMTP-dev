# Keithley Dmm6500 Mtp 6500

@Metadata {
    @DisplayName: "Keithley Dmm6500 Mtp 6500"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Keithley Dmm6500 Mtp 6500 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x05e6 |
| Product ID | 0x6500 |
| Device Info Pattern | `None` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 262 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 300000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Keithley DMM6500 6.5-digit touchscreen multimeter.
- USB MTP for measurement data and screenshot export.
- High-precision bench multimeter by Tektronix/Keithley.
- Exports CSV measurement logs via MTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
