# Canon Eos 5D Mark Iv 3281

@Metadata {
    @DisplayName: "Canon Eos 5D Mark Iv 3281"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos 5D Mark Iv 3281 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x3281 |
| Device Info Pattern | `.*Canon.*EOS.*` |
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
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Canon EOS 5D-Mark-IV uses PTP over USB.
- Camera must be in PTP/MTP mode (not PC Connection mode).
- Large RAW/CR2/CR3 files (>20 MB) may require extended ioTimeoutMs.
- Event pump needed for capture events (0x4001 ObjectAdded).
- 30.4 MP full-frame, CF+SD dual slot.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
