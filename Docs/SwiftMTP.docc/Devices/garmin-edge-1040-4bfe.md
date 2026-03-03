# Garmin Edge 1040 4Bfe

@Metadata {
    @DisplayName: "Garmin Edge 1040 4Bfe"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Garmin Edge 1040 4Bfe MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x091e |
| Product ID | 0x4bfe |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Prefer Object Property List | No |

## Notes

- Garmin Edge 1040 cycling computer. Presents as USB mass storage by default; some firmware versions expose MTP. Custom Garmin interface class. Large activity files may need patient timeouts.