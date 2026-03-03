# Magic Leap 2 Compute 0002

@Metadata {
    @DisplayName: "Magic Leap 2 Compute 0002"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Magic Leap 2 Compute 0002 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2e58 |
| Product ID | 0x0002 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 12000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
