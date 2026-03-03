# Canon Eos M50 Ii 32F9

@Metadata {
    @DisplayName: "Canon Eos M50 Ii 32F9"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos M50 Ii 32F9 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x32f9 |
| Device Info Pattern | `.*Canon.*EOS.*` |
| Status | Proposed |

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

- Canon EOS M50-II uses PTP over USB.
- Camera must be in PTP/MTP mode (not PC Connection mode).
- Large RAW/CR2/CR3 files (>20 MB) may require extended ioTimeoutMs.
- Event pump needed for capture events (0x4001 ObjectAdded).
- 24.1 MP APS-C mirrorless with OLED EVF.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-14
- **Commit**: <pending>

### Evidence Artifacts
