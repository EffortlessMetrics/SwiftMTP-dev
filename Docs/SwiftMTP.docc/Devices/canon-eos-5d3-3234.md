# Canon Eos 5D3 3234

@Metadata {
    @DisplayName: "Canon Eos 5D3 3234"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos 5D3 3234 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x3234 |
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
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- Canon EOS 5D Mark III. Full-frame DSLR, 22.3 MP. CR2 RAW files ~25 MB.
- PTP vendor extension: canon.com:1.0. Supports Canon EOS operation codes (0x9101-0x91FF).
- Confirmed: Image Capture, Trigger Capture, Liveview, Configuration via gphoto2.
- Supports GetPartialObject (0x9107), GetEvent (0x9116), RemoteRelease (0x910F).
- EOS KeepDeviceOn (0x911D) required for long tethered sessions.