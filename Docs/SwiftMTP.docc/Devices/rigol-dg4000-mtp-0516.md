# Rigol Dg4000 Mtp 0516

@Metadata {
    @DisplayName: "Rigol Dg4000 Mtp 0516"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Rigol Dg4000 Mtp 0516 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1ab1 |
| Product ID | 0x0516 |
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

- Rigol DG4000 series arbitrary waveform generator.
- USB MTP for loading custom waveforms.
- Dual-channel, up to 200MHz output.
- MTP used for ARB waveform file transfer.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
