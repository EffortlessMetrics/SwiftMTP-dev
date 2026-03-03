# Nothing Phone 1 E512

@Metadata {
    @DisplayName: "Nothing Phone 1 E512"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nothing Phone 1 E512 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2970 |
| Product ID | 0xe512 |
| Device Info Pattern | `None` |
| Status | Experimental |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Nothing Phone (1) Glyph Interface. Snapdragon 778G+. USB-C MTP.