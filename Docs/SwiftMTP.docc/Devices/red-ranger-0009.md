# Red Ranger 0009

@Metadata {
    @DisplayName: "Red Ranger 0009"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Red Ranger 0009 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1419 |
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

- RED RANGER cinema camera.
- Integrated cinema camera with built-in V-mount and gold-mount.
- USB 3.2 for R3D file transfer.
- All-in-one body designed for studio and field production.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
