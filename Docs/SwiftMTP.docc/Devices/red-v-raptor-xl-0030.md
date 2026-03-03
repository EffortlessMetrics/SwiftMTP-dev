# Red V Raptor Xl 0030

@Metadata {
    @DisplayName: "Red V Raptor Xl 0030"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Red V Raptor Xl 0030 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04f1 |
| Product ID | 0x0030 |
| Device Info Pattern | `.*RED.*V-RAPTOR.*XL.*` |
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
| I/O Timeout | 60000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 600000 | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- RED V-RAPTOR XL 8K VV cinema camera.
- VistaVision 8K sensor.
- USB-C for media offload.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
