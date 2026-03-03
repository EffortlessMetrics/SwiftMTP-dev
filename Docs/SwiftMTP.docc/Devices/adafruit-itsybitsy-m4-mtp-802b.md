# Adafruit Itsybitsy M4 Mtp 802B

@Metadata {
    @DisplayName: "Adafruit Itsybitsy M4 Mtp 802B"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Adafruit Itsybitsy M4 Mtp 802B MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x239a |
| Product ID | 0x802b |
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

- Adafruit ItsyBitsy M4 Express (SAMD51) with TinyUSB MTP responder. Limited flash storage; conservative timeouts needed.