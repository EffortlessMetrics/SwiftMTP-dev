# Samsung Galaxy Xcover 5 6953

@Metadata {
    @DisplayName: "Samsung Galaxy Xcover 5 6953"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Samsung Galaxy Xcover 5 6953 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04e8 |
| Product ID | 0x6953 |
| Device Info Pattern | `.*Galaxy.*XCover.*5.*` |
| Status | Experimental |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 5000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
