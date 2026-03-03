# Sony Alpha A6700 0E78

@Metadata {
    @DisplayName: "Sony Alpha A6700 0E78"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sony Alpha A6700 0E78 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x054c |
| Product ID | 0x0e78 |
| Device Info Pattern | `.*Sony.*ILCE-6700.*` |
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
| Handshake Timeout | 15000 | ms |
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

- Sony Alpha A6700 (ILCE-6700) in PC Control mode. VID:PID from gphoto2 (0x054c:0x0e78).
- APS-C mirrorless, 26 MP. ARW RAW files ~30 MB.
- Sony cameras require Sony vendor extension for remote control.
- Confirmed PTP_CAP and PTP_CAP_PREVIEW in gphoto2.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
