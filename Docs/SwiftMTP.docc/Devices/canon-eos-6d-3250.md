# Canon Eos 6D 3250

@Metadata {
    @DisplayName: "Canon Eos 6D 3250"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos 6D 3250 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x3250 |
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

- Canon EOS 6D uses PTP over USB.
- Camera must be in PTP/MTP mode (not PC Connection mode).
- Large RAW/CR2/CR3 files (>20 MB) may require extended ioTimeoutMs.
- Event pump needed for capture events (0x4001 ObjectAdded).
- 20.2 MP full-frame, first Canon DSLR with Wi-Fi.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-14
- **Commit**: <pending>

### Evidence Artifacts
