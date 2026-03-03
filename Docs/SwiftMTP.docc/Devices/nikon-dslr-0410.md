# Nikon Dslr 0410

@Metadata {
    @DisplayName: "Nikon Dslr 0410"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon Dslr 0410 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x0410 |
| Device Info Pattern | `.*Nikon.*` |
| Status | Promoted |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 300 | ms |
| Event Pump Delay | 100 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Nikon DSLR (generic PID 0x0410). PTP vendor extension ID: 0x0000000A.
- Nikon PTP vendor extensions: GetEvent (0x90C7), DeviceReady (0x90C8), GetVendorPropCodes (0x90CA).
- Liveview: StartLiveView (0x9201), EndLiveView (0x9202), GetLiveViewImg (0x9203).
- Remote capture: InitiateCaptureRecInSdram (0x90C0), AfDrive (0x90C1), AfCaptureSDRAM (0x90CB).
- Camera must be in MTP/PTP mode via Settings > USB Options.
- NEF raw files are large (15-30 MB); extend ioTimeoutMs for large transfers.
- Nikon DeviceReady (0x90C8) should be polled before operations to check camera state.
- GetObjectSize (0x9421) returns 64-bit file size for large video files.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-02-25
- **Commit**: <pending>

### Evidence Artifacts
