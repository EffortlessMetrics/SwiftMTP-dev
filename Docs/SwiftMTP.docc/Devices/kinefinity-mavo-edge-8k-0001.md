# Kinefinity Mavo Edge 8K 0001

@Metadata {
    @DisplayName: "Kinefinity Mavo Edge 8K 0001"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kinefinity Mavo Edge 8K 0001 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x33f8 |
| Product ID | 0x0001 |
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

- Kinefinity MAVO Edge 8K cinema camera.
- Full-frame 8K sensor with global shutter option.
- USB-C for KineRAW and ProRes file transfer.
- Chinese cinema camera with interchangeable sensor mount.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
