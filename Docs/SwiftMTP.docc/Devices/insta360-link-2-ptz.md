# Insta360 Link 2 Ptz

@Metadata {
    @DisplayName: "Insta360 Link 2 Ptz"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Insta360 Link 2 Ptz MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0xa000 |
| Product ID | 0x016d |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
