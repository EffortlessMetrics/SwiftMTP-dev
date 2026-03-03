# Crosscall Action X5 9132

@Metadata {
    @DisplayName: "Crosscall Action X5 9132"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Crosscall Action X5 9132 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x109b |
| Product ID | 0x9132 |
| Device Info Pattern | `.*Crosscall.*Action.X5.*` |
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
