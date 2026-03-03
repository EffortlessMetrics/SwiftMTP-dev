# Carlinkit 4 Wireless Carplay

@Metadata {
    @DisplayName: "Carlinkit 4 Wireless Carplay"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Carlinkit 4 Wireless Carplay MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0xb000 |
| Product ID | 0x0001 |
| Device Info Pattern | `None` |
| Status | Experimental |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 5000 | ms |
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | 5000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
