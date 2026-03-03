# Huawei Nova 11 10D7

@Metadata {
    @DisplayName: "Huawei Nova 11 10D7"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Huawei Nova 11 10D7 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x12d1 |
| Product ID | 0x10d7 |
| Device Info Pattern | `.*nova 11[^0-9].*` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | default | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | default | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|