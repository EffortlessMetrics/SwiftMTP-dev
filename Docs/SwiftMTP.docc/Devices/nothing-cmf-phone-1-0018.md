# Nothing Cmf Phone 1 0018

@Metadata {
    @DisplayName: "Nothing Cmf Phone 1 0018"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nothing Cmf Phone 1 0018 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2970 |
| Product ID | 0x0018 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- CMF Phone 1 by Nothing. Budget MTP endpoint.
- NothingOS-based Android MTP stack. MediaTek Dimensity 7300.
- Standard Android MTP behavior. Kernel detach required on macOS.