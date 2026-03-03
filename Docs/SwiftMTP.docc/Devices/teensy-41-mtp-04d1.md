# Teensy 41 Mtp 04D1

@Metadata {
    @DisplayName: "Teensy 41 Mtp 04D1"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Teensy 41 Mtp 04D1 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x16c0 |
| Product ID | 0x04d1 |
| Device Info Pattern | `None` |
| Status | Experimental |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 262 KB | bytes |
| Handshake Timeout | 12000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 30000 | ms |
| Overall Deadline | 300000 | ms || Stabilization Delay | 1000 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|
## Notes

- Teensy 4.1 with MTP_Teensy library. Exposes SD card or PSRAM storage via MTP. Uses PJRC VID. Well-tested MTP implementation for embedded; supports basic file operations.