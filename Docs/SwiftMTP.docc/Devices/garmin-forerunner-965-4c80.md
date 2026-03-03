# Garmin Forerunner 965 4C80

@Metadata {
    @DisplayName: "Garmin Forerunner 965 4C80"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Garmin Forerunner 965 4C80 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x091e |
| Product ID | 0x4c80 |
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

- Garmin Forerunner 965 GPS watch. MTP mode for music/map transfers. Small storage; Garmin custom USB class. Activity files are typically small but map tiles can be large.