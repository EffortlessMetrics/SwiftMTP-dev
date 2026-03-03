# Honor Magic6 0102

@Metadata {
    @DisplayName: "Honor Magic6 0102"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Honor Magic6 0102 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x3567 |
| Product ID | 0x0102 |
| Device Info Pattern | `.*Magic ?6[^0-9].*` |
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