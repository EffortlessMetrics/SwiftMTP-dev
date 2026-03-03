# Sonos Roam Mtp 0610

@Metadata {
    @DisplayName: "Sonos Roam Mtp 0610"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sonos Roam Mtp 0610 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1e54 |
| Product ID | 0x0610 |
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
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Sonos Roam portable Bluetooth/Wi-Fi speaker.
- USB-C port used for charging and MTP diagnostics.
- Compact triangular design for outdoor use.
- MTP access for firmware and diagnostic logs.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
