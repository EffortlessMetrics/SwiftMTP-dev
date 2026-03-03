# Hmd Skyline 0701

@Metadata {
    @DisplayName: "Hmd Skyline 0701"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hmd Skyline 0701 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0421 |
| Product ID | 0x0701 |
| Device Info Pattern | `.*HMD Skyline.*` |
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