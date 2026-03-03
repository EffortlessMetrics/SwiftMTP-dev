# Kenwood Dmx Car Headunit 0200

@Metadata {
    @DisplayName: "Kenwood Dmx Car Headunit 0200"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kenwood Dmx Car Headunit 0200 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0b28 |
| Product ID | 0x0200 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 12000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 800 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| Prefer Object Property List | No |

## Notes

- Kenwood DMX series car head unit with MTP media playback support. Reads music libraries via MTP. Conservative settings for automotive USB environment.