# Red V Raptor Xl 8K 0007

@Metadata {
    @DisplayName: "Red V Raptor Xl 8K 0007"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Red V Raptor Xl 8K 0007 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1419 |
| Product ID | 0x0007 |
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

- RED V-RAPTOR XL 8K VV cinema camera.
- Full-frame 8K sensor with global shutter in XL form factor.
- USB 3.2 for high-speed R3D file offload.
- Extended body with integrated V-mount battery plate.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
