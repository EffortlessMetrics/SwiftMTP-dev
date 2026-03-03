# Sjcam Sj20 0209

@Metadata {
    @DisplayName: "Sjcam Sj20 0209"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sjcam Sj20 0209 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1224 |
| Product ID | 0x0209 |
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
| Maximum Chunk Size | 1 MB | bytes |
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

- SJCAM SJ20 dual-screen action camera.
- Latest generation with improved stabilization.
- USB-C MTP mode for media transfer.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
