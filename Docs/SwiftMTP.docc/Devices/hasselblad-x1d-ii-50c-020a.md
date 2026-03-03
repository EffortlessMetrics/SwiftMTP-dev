# Hasselblad X1D Ii 50C 020A

@Metadata {
    @DisplayName: "Hasselblad X1D Ii 50C 020A"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hasselblad X1D Ii 50C 020A MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a0 |
| Product ID | 0x020a |
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
| I/O Timeout | 20000 | ms |
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

- Hasselblad X1D II mirrorless medium format camera.
- 50MP sensor, RAW files around 70-80MB.
- PTP/MTP mode for file transfer and tethering.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
