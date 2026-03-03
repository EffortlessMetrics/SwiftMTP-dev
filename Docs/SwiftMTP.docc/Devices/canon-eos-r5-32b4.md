# Canon Eos R5 32B4

@Metadata {
    @DisplayName: "Canon Eos R5 32B4"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos R5 32B4 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x32b4 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 45000 | ms |
| Inactivity Timeout | 20000 | ms |
| Overall Deadline | 300000 | ms |
## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- Canon EOS R5. Full-frame mirrorless, 45 MP. CR3 RAW files ~50 MB, 8K video files can exceed 1 GB.
- PTP vendor extension: canon.com:1.0 with EOS digital extensions (0x9101-0x91FF).
- Confirmed by gphoto2: Image Capture, Trigger Capture, Liveview, Configuration.
- Supports EOS GetPartialObject (0x9107), GetObject64 (0x9170/0x9171), GetPartialObject64 (0x9172).
- 64-bit object operations essential for large 8K RAW video files.
- Canon CCAPI (Camera Control API) also available over WiFi.
- Event polling via EOS GetEvent (0x9116). Supports SetRemoteShootingMode (0x9086).