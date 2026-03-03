# Pioneer Avh Car Headunit 0160

@Metadata {
    @DisplayName: "Pioneer Avh Car Headunit 0160"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Pioneer Avh Car Headunit 0160 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x08e4 |
| Product ID | 0x0160 |
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

- Pioneer AVH series car head unit with USB MTP support. Used for music library transfer. Custom Pioneer USB interface. Patient timeouts needed; automotive USB power can be noisy.