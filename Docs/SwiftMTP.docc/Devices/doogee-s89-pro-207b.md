# Doogee S89 Pro 207B

@Metadata {
    @DisplayName: "Doogee S89 Pro 207B"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Doogee S89 Pro 207B MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e8d |
| Product ID | 0x207b |
| Device Info Pattern | `.*Doogee.*S89.*Pro.*` |
| Status | Experimental |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 5000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
