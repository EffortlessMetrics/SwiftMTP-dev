# Fujifilm X100Vi 0305

@Metadata {
    @DisplayName: "Fujifilm X100Vi 0305"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Fujifilm X100Vi 0305 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04cb |
| Product ID | 0x0305 |
| Device Info Pattern | `.*FUJIFILM.*X100VI.*` |
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

- Fujifilm X100VI uses PTP over USB. VID:PID verified via gphoto2 (0x04cb:0x0305).
- APS-C fixed-lens compact, 40.2 MP. RAF RAW files ~80 MB (uncompressed).
- Fujifilm cameras use Fuji vendor PTP extensions.
- gphoto2 lists without capture flags; file transfer only.
- Very popular camera; large RAF file sizes require generous ioTimeoutMs.
## Provenance

- **Author**: Unknown
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
