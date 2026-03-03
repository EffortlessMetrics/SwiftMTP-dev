# Hasselblad X1D 50C 020C

@Metadata {
    @DisplayName: "Hasselblad X1D 50C 020C"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hasselblad X1D 50C 020C MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a0 |
| Product ID | 0x020c |
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

- Hasselblad X1D-50c first-generation medium format mirrorless.
- 50MP medium format CMOS sensor (43.8x32.9mm).
- USB-C PTP/MTP for Hasselblad 3FR RAW transfer.
- World's first mirrorless medium format digital camera.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
