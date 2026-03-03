# Jvc Kw Mtp 0410

@Metadata {
    @DisplayName: "Jvc Kw Mtp 0410"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Jvc Kw Mtp 0410 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04f1 |
| Product ID | 0x0410 |
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

- JVC KW-series double-DIN car stereo receivers.
- USB MTP support for media library access.
- Bluetooth and USB dual connectivity.
- Variable color illumination with MTP media.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
