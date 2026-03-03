# Sigma Sd15 0039

@Metadata {
    @DisplayName: "Sigma Sd15 0039"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sigma Sd15 0039 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1003 |
| Product ID | 0x0039 |
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
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Sigma SD15 DSLR camera.
- APS-C Foveon X3 sensor (14MP total, 4.7MP x 3 layers).
- USB 2.0 PTP for Sigma X3F RAW transfer.
- Entry-level SA-mount body with Foveon sensor.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
