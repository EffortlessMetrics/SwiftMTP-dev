# Alpine Ilx Mtp 0310

@Metadata {
    @DisplayName: "Alpine Ilx Mtp 0310"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Alpine Ilx Mtp 0310 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0db6 |
| Product ID | 0x0310 |
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

- Alpine iLX-series digital media receivers.
- MTP support for USB media in car audio systems.
- Halo-series floating touchscreen design.
- CarPlay/Android Auto with MTP USB fallback.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
