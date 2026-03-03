# Marshall Stanmore Mtp 0820

@Metadata {
    @DisplayName: "Marshall Stanmore Mtp 0820"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Marshall Stanmore Mtp 0820 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2c97 |
| Product ID | 0x0820 |
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

- Marshall Stanmore III wireless home speaker.
- USB MTP for local media and firmware updates.
- Vintage amplifier design with modern connectivity.
- Spotify Connect and AirPlay 2 capable.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
