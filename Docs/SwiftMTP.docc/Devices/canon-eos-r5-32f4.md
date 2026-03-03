# Canon Eos R5 32F4

@Metadata {
    @DisplayName: "Canon Eos R5 32F4"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos R5 32F4 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x32f4 |
| Device Info Pattern | `.*Canon.*EOS.*R5.*` |
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
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Canon EOS R5 uses PTP over USB. VID:PID verified via gphoto2 (0x04a9:0x32f4).
- Camera must be in PTP/MTP mode (not PC Connection mode).
- Large RAW CR3 files (~50 MB for 45 MP) may require extended ioTimeoutMs.
- Event pump needed for capture events (0x4001 ObjectAdded).
- 45 MP full-frame mirrorless. Supports 8K video recording.
- Confirmed PTP_CAP and PTP_CAP_PREVIEW in gphoto2.
## Provenance

- **Author**: Unknown
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
