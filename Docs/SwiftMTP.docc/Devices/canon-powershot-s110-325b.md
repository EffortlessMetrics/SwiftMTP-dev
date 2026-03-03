# Canon Powershot S110 325B

@Metadata {
    @DisplayName: "Canon Powershot S110 325B"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Powershot S110 325B MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x325b |
| Device Info Pattern | `.*Canon.*` |
| Status | Proposed |

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
| I/O Timeout | 25000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 150000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Canon PowerShot S110 — compact/bridge/mirrorless camera using PTP over USB.
- Camera must be in PTP/MTP mode (not PC Connection mode).
- JPEG and RAW (CR2/CR3) files supported.
- Event pump needed for capture events (0x4001 ObjectAdded).
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-17
- **Commit**: <pending>

### Evidence Artifacts
