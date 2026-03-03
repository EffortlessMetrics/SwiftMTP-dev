# Blackmagic Pocket 4K 0009

@Metadata {
    @DisplayName: "Blackmagic Pocket 4K 0009"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Blackmagic Pocket 4K 0009 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1edb |
| Product ID | 0x0009 |
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
| Maximum Chunk Size | 8.4 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 60000 | ms |
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

- Blackmagic Pocket Cinema Camera 4K.
- 4/3 sensor with 4096x2160 DCI 4K resolution.
- USB-C for Blackmagic RAW and ProRes file transfer.
- Compact cinema camera with MFT lens mount.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
