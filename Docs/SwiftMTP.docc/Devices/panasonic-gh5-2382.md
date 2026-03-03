# Panasonic Gh5 2382

@Metadata {
    @DisplayName: "Panasonic Gh5 2382"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Panasonic Gh5 2382 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04da |
| Product ID | 0x2382 |
| Device Info Pattern | `.*Panasonic.*DC-GH5.*` |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Panasonic DC-GH5 uses PTP over USB. VID:PID verified via gphoto2 (0x04da:0x2382).
- Micro Four Thirds, 20.3 MP. RW2 RAW files ~25 MB.
- Panasonic uses Microsoft MTP vendor extension ID but needs special MTP Initiator setup.
- gphoto2 applies Panasonic-specific fixups (SetProperty, InitiateCapture, Liveview).
- Confirmed PTP_CAP and PTP_CAP_PREVIEW in gphoto2.
- Multiple Panasonic models may share PID 0x2382 in PTP mode.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
