# Rigol Ds1054Z Mtp 0514

@Metadata {
    @DisplayName: "Rigol Ds1054Z Mtp 0514"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Rigol Ds1054Z Mtp 0514 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1ab1 |
| Product ID | 0x0514 |
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

- Rigol DS1054Z 4-channel 50MHz digital oscilloscope.
- USB MTP for screenshot and waveform data export.
- Popular entry-level bench oscilloscope.
- Exports PNG screenshots and CSV waveform data via MTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
