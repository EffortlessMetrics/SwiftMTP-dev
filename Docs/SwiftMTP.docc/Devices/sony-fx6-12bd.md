# Sony Fx6 12Bd

@Metadata {
    @DisplayName: "Sony Fx6 12Bd"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sony Fx6 12Bd MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x054c |
| Product ID | 0x12bd |
| Device Info Pattern | `.*Sony.*FX6.*` |
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
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Sony FX6 full-frame cinema camera.
- 10.2MP with S-Cinetone and 4K 120p.
- CFexpress Type A + SD.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
