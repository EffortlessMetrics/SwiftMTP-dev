# Alpine Halo Mtp 0320

@Metadata {
    @DisplayName: "Alpine Halo Mtp 0320"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Alpine Halo Mtp 0320 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0db6 |
| Product ID | 0x0320 |
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
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
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

- Alpine Halo9 premium floating-screen receiver.
- 9-inch screen with MTP USB media connectivity.
- HDMI input with MTP file browsing support.
- High-end aftermarket head unit.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
