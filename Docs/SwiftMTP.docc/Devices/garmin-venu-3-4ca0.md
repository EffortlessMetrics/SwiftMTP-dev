# Garmin Venu 3 4Ca0

@Metadata {
    @DisplayName: "Garmin Venu 3 4Ca0"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Garmin Venu 3 4Ca0 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x091e |
| Product ID | 0x4ca0 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 262 KB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 20000 | ms |
| Overall Deadline | 180000 | ms |
## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Prefer Object Property List | No |

## Notes

- Garmin Venu 3 GPS smartwatch. MTP mode for music and app data transfer. Uses Garmin proprietary USB class. Conservative transfer settings recommended.