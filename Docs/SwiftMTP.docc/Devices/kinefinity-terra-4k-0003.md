# Kinefinity Terra 4K 0003

@Metadata {
    @DisplayName: "Kinefinity Terra 4K 0003"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kinefinity Terra 4K 0003 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x33f8 |
| Product ID | 0x0003 |
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

- Kinefinity TERRA 4K Super 35mm cinema camera.
- Super 35mm 4K sensor in compact body.
- USB-C for KineRAW file transfer.
- Entry-level cinema camera in Kinefinity ecosystem.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
