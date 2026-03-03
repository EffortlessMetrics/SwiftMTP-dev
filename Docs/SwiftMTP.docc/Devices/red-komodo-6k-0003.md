# Red Komodo 6K 0003

@Metadata {
    @DisplayName: "Red Komodo 6K 0003"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Red Komodo 6K 0003 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1419 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
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

- RED KOMODO 6K compact cinema camera.
- Super 35 global shutter sensor.
- USB-C for R3D file offload from CFast 2.0 cards.
- Compact form factor, same REDCODE RAW workflow.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
