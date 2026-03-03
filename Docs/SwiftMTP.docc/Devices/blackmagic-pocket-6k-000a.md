# Blackmagic Pocket 6K 000A

@Metadata {
    @DisplayName: "Blackmagic Pocket 6K 000A"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Blackmagic Pocket 6K 000A MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1edb |
| Product ID | 0x000a |
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

- Blackmagic Pocket Cinema Camera 6K.
- Super 35mm sensor with 6144x3456 resolution.
- USB-C for Blackmagic RAW and ProRes file transfer.
- EF-mount compact cinema camera with 6K capture.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
