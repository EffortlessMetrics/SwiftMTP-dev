# Garmin Fenix 7 4C3E

@Metadata {
    @DisplayName: "Garmin Fenix 7 4C3E"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Garmin Fenix 7 4C3E MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x091e |
| Product ID | 0x4c3e |
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

- Garmin Fenix 7 series multisport watch. Typically uses Garmin MTP mode for map/activity transfer. Custom interface class. Watch storage is limited; patient timeouts needed for map transfers.