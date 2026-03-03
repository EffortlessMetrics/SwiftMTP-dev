# Kenwood Dnx Mtp 0220

@Metadata {
    @DisplayName: "Kenwood Dnx Mtp 0220"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kenwood Dnx Mtp 0220 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0b67 |
| Product ID | 0x0220 |
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
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Kenwood DNX-series navigation multimedia receivers.
- Built-in GPS navigation with MTP media support.
- Dual-zone entertainment with USB MTP connectivity.
- Garmin navigation engine with music file browsing.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
