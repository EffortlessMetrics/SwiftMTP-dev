# Tektronix Tbs2000 Mtp 0368

@Metadata {
    @DisplayName: "Tektronix Tbs2000 Mtp 0368"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Tektronix Tbs2000 Mtp 0368 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0699 |
| Product ID | 0x0368 |
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
| Maximum Chunk Size | 262 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 300000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Tektronix TBS2000B series digital oscilloscope.
- USB MTP for waveform and screenshot export.
- 200MHz bandwidth, 2GS/s sample rate.
- Front-panel USB port for MTP data transfer.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
