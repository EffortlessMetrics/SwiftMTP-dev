# Hasselblad H3Dii 50 0211

@Metadata {
    @DisplayName: "Hasselblad H3Dii 50 0211"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hasselblad H3Dii 50 0211 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x25b7 |
| Product ID | 0x0211 |
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

- Hasselblad H3D II-50 medium format camera.
- 50MP medium format CCD sensor.
- USB 2.0 PTP for 3FR RAW file transfer.
- Legacy H-system body with integrated digital back.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
