# Kinefinity Mavo S35 0004

@Metadata {
    @DisplayName: "Kinefinity Mavo S35 0004"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kinefinity Mavo S35 0004 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x33f8 |
| Product ID | 0x0004 |
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

- Kinefinity MAVO S35 Super 35mm cinema camera.
- Super 35mm 6K sensor.
- USB-C for KineRAW and ProRes file transfer.
- Mid-range Super 35mm cinema camera.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
