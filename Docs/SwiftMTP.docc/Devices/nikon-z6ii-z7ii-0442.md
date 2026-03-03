# Nikon Z6Ii Z7Ii 0442

@Metadata {
    @DisplayName: "Nikon Z6Ii Z7Ii 0442"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon Z6Ii Z7Ii 0442 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x0442 |
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
| Handshake Timeout | default | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 300000 | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Nikon Z7 (PID 0x0442). Full-frame mirrorless, 45.7 MP. NEF RAW files ~50 MB.
- PTP vendor extension ID: 0x0000000A. Nikon Z-mount mirrorless camera.
- Nikon vendor extensions: GetEvent (0x90C7), DeviceReady (0x90C8), GetVendorPropCodes (0x90CA).
- Liveview: StartLiveView (0x9201), GetLiveViewImg (0x9203), GetLiveViewImageEx (0x9428).
- High-speed transfer: GetPartialObjectHiSpeed (0x9400) for fast bulk downloads.
- GetPartialObjectEx (0x9431) supports 64-bit offsets for large video files.
- Dual card slots (XQD/CFexpress + SD). Storage enumeration may return multiple IDs.