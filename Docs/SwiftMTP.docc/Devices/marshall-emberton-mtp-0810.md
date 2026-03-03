# Marshall Emberton Mtp 0810

@Metadata {
    @DisplayName: "Marshall Emberton Mtp 0810"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Marshall Emberton Mtp 0810 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2c97 |
| Product ID | 0x0810 |
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
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Marshall Emberton II portable Bluetooth speaker.
- USB-C MTP for firmware updates and diagnostics.
- IP67 rated, 30+ hour battery life.
- Iconic Marshall guitar-amp design aesthetic.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
