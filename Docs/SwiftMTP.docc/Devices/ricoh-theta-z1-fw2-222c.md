# Ricoh Theta Z1 Fw2 222C

@Metadata {
    @DisplayName: "Ricoh Theta Z1 Fw2 222C"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Ricoh Theta Z1 Fw2 222C MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x05ca |
| Product ID | 0x222c |
| Device Info Pattern | `.*Ricoh.*THETA Z1.*` |
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
| Maximum Chunk Size | 1 MB | bytes |
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

- Ricoh THETA Z1 360-degree camera.
- 1-inch dual sensors, 23MP per side.
- USB-C PTP for file transfer.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
