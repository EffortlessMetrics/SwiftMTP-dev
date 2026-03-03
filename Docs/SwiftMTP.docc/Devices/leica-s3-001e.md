# Leica S3 001E

@Metadata {
    @DisplayName: "Leica S3 001E"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Leica S3 001E MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1a98 |
| Product ID | 0x001e |
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

- Leica S3 medium format camera.
- 64MP medium format CMOS sensor (30x45mm).
- USB-C PTP for large DNG RAW file transfer (~80-130MB).
- Professional medium format system with Leica S-mount.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
