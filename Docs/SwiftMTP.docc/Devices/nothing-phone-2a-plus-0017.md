# Nothing Phone 2A Plus 0017

@Metadata {
    @DisplayName: "Nothing Phone 2A Plus 0017"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nothing Phone 2A Plus 0017 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2970 |
| Product ID | 0x0017 |
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

- Nothing Phone (2a) Plus alternate PID. Community-reported MTP endpoint.
- NothingOS (Android 14 based) MTP stack.
- Kernel detach required on macOS.