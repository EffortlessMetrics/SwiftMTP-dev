# Fujifilm Xh2S 02F0

@Metadata {
    @DisplayName: "Fujifilm Xh2S 02F0"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Fujifilm Xh2S 02F0 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04cb |
| Product ID | 0x02f0 |
| Device Info Pattern | `.*FUJIFILM.*X-H2S.*` |
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
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Fujifilm X-H2S uses PTP over USB. VID:PID verified via gphoto2 (0x04cb:0x02f0).
- APS-C mirrorless, 26.1 MP stacked sensor. RAF RAW files ~30 MB.
- Fujifilm cameras use Fuji vendor PTP extensions.
- gphoto2 lists without capture flags; tethering may be limited.
- Fast burst shooting may generate many ObjectAdded events.
## Provenance

- **Author**: Unknown
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
