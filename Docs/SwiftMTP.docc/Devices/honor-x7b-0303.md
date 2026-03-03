# Honor X7B 0303

@Metadata {
    @DisplayName: "Honor X7B 0303"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Honor X7B 0303 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x3567 |
| Product ID | 0x0303 |
| Device Info Pattern | `.*Honor X7b.*` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | default | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | default | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|