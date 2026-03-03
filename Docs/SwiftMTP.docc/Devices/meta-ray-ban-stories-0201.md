# Meta Ray Ban Stories 0201

@Metadata {
    @DisplayName: "Meta Ray Ban Stories 0201"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Meta Ray Ban Stories 0201 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2833 |
| Product ID | 0x0201 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
