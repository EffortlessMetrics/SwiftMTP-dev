# Sigma Sd1 Merrill 0038

@Metadata {
    @DisplayName: "Sigma Sd1 Merrill 0038"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sigma Sd1 Merrill 0038 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1003 |
| Product ID | 0x0038 |
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

- Sigma SD1 Merrill DSLR camera.
- APS-C Foveon X3 Merrill sensor (46MP total, 15.3MP x 3 layers).
- USB 2.0 PTP for Sigma X3F RAW transfer.
- Flagship Foveon DSLR with three-layer direct image sensor.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
