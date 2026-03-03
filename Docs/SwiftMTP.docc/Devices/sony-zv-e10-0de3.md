# Sony Zv E10 0De3

@Metadata {
    @DisplayName: "Sony Zv E10 0De3"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Sony Zv E10 0De3 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x054c |
| Product ID | 0x0de3 |
| Device Info Pattern | `.*Sony.*ZV-E10.*` |
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

- Sony ZV-E10 in MTP mode. VID:PID verified via gphoto2 (0x054c:0x0de3).
- PID 0x0d97 is PC Remote Control mode with capture support.
- APS-C mirrorless vlogging camera, 24.2 MP.
- Sony cameras require Sony vendor extension for remote control.
- Confirmed in gphoto2 as ZV-E10 (MTP mode).
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
