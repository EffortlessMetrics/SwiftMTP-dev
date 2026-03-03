# Sony Alpha A7Iv 0Da6

@Metadata {
    @DisplayName: "Sony Alpha A7Iv 0Da6"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sony Alpha A7Iv 0Da6 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x054c |
| Product ID | 0x0da6 |
| Device Info Pattern | `.*Sony.*ILCE-7M4.*` |
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

- Sony Alpha A7 IV (ILCE-7M4) in MTP mode. VID:PID verified via gphoto2 (0x054c:0x0da6).
- PID 0x0da7 is PC Remote Control mode with capture support.
- Full-frame mirrorless, 33 MP. ARW RAW files ~35 MB.
- Sony cameras require Sony vendor extension for remote control.
- MTP mode provides file access; PC Control mode adds capture.
- Confirmed in gphoto2 as Alpha-A7 IV (MTP mode).
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
