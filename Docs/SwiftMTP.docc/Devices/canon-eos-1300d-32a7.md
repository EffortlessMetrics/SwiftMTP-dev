# Canon Eos 1300D 32A7

@Metadata {
    @DisplayName: "Canon Eos 1300D 32A7"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos 1300D 32A7 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x32a7 |
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
| Maximum Chunk Size | 1 MB | bytes |
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

- Canon EOS 1300D / Rebel T6 — entry-level DSLR with Wi-Fi and NFC (2016)
- Camera must be in PTP/MTP mode (not PC Connection mode).
- Large RAW files (>20 MB) may require extended ioTimeoutMs.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-02-28
- **Commit**: <pending>

### Evidence Artifacts
