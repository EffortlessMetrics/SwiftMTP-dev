# Creative Muvo Squared 4173

@Metadata {
    @DisplayName: "Creative Muvo Squared 4173"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Creative Muvo Squared 4173 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x041e |
| Product ID | 0x4173 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |
