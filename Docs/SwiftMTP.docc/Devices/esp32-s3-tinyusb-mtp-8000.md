# Esp32 S3 Tinyusb Mtp 8000

@Metadata {
    @DisplayName: "Esp32 S3 Tinyusb Mtp 8000"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Esp32 S3 Tinyusb Mtp 8000 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x303a |
| Product ID | 0x8000 |
| Device Info Pattern | `None` |
| Status | Proposed |

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

- Espressif ESP32-S3 with native USB and TinyUSB MTP stack. Exposes SPI flash or SD card storage. Very constrained; basic MTP operations only. PID 0x8000 is a common TinyUSB default.