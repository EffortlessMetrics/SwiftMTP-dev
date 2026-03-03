# Leica M11 Monochrom 0064

@Metadata {
    @DisplayName: "Leica M11 Monochrom 0064"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Leica M11 Monochrom 0064 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1a98 |
| Product ID | 0x0064 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 240000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Leica M11 Monochrom black-and-white rangefinder.
- 60.3MP full-frame monochrome sensor, no Bayer filter.
- USB-C PTP for DNG RAW transfer.
- Monochrome-only sensor yields exceptional tonal range.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
