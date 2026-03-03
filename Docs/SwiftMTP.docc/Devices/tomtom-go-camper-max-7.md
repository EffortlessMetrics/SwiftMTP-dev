# Tomtom Go Camper Max 7

@Metadata {
    @DisplayName: "Tomtom Go Camper Max 7"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Tomtom Go Camper Max 7 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0xa000 |
| Product ID | 0x00e4 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
