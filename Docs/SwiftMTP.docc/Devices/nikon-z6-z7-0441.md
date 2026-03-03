# Nikon Z6 Z7 0441

@Metadata {
    @DisplayName: "Nikon Z6 Z7 0441"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon Z6 Z7 0441 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x0441 |
| Device Info Pattern | `.*Nikon.*D850.*` |
| Status | Experimental |

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
| Handshake Timeout | default | ms |
| I/O Timeout | 45000 | ms |
| Inactivity Timeout | 20000 | ms |
| Overall Deadline | 300000 | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Nikon D850 (PID 0x0441 per gphoto2). Full-frame DSLR, 45.7 MP. NEF RAW files ~50 MB.
- PTP vendor extension ID: 0x0000000A. Vendor extensions in 0x90xx and 0x94xx ranges.
- Nikon extensions: GetEvent (0x90C7), DeviceReady (0x90C8), StartLiveView (0x9201).
- High-speed partial object transfer: GetPartialObjectHiSpeed (0x9400) for fast bulk downloads.
- GetObjectSize (0x9421) returns 64-bit size. GetObjectsMetaData (0x9434) for batch metadata.
- Confirmed PTP_CAP and PTP_CAP_PREVIEW capabilities in gphoto2.
- Z7 is PID 0x0442, Z6 is PID 0x0443 (separate entries). This entry is D850.