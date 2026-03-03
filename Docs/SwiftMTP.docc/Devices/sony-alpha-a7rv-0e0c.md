# Sony Alpha A7Rv 0E0C

@Metadata {
    @DisplayName: "Sony Alpha A7Rv 0E0C"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sony Alpha A7Rv 0E0C MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x054c |
| Product ID | 0x0e0c |
| Device Info Pattern | `.*Sony.*ILCE-7RM5.*` |
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
| Maximum Chunk Size | 8.4 MB | bytes |
| Handshake Timeout | 15000 | ms |
| I/O Timeout | 45000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Sony Alpha A7R V (ILCE-7RM5) in PC Control mode. VID:PID from gphoto2 (0x054c:0x0e0c).
- Full-frame mirrorless, 61 MP. ARW RAW files ~120 MB (uncompressed).
- Very large file sizes require generous ioTimeoutMs.
- Sony cameras require Sony vendor extension for remote control.
- Confirmed PTP_CAP and PTP_CAP_PREVIEW in gphoto2.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
