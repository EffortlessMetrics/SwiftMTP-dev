# Hasselblad Cfv Ii 50C 0208

@Metadata {
    @DisplayName: "Hasselblad Cfv Ii 50C 0208"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hasselblad Cfv Ii 50C 0208 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a0 |
| Product ID | 0x0208 |
| Device Info Pattern | `None` |
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
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Hasselblad CFV II 50C digital back for V-system cameras.
- Uses PTP/MTP over USB for tethered shooting and file transfer.
- Large medium format RAW files (50MP) require generous timeouts.
- Camera must be powered on and in USB transfer mode.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
