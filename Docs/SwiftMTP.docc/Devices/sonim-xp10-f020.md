# Sonim Xp10 F020

@Metadata {
    @DisplayName: "Sonim Xp10 F020"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sonim Xp10 F020 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x05c6 |
| Product ID | 0xf020 |
| Device Info Pattern | `.*Sonim.*XP10.*` |
| Status | Experimental |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
