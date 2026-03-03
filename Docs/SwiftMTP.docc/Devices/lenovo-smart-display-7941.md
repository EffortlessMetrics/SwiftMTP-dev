# Lenovo Smart Display 7941

@Metadata {
    @DisplayName: "Lenovo Smart Display 7941"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Lenovo Smart Display 7941 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x17ef |
| Product ID | 0x7941 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|
## Notes

- Lenovo Smart Display with Google Assistant. MTP requires developer mode. Limited internal storage. Uses standard Android MTP stack on embedded Qualcomm platform.