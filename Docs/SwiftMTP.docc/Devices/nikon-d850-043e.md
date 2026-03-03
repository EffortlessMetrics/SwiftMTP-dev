# Nikon D850 043E

@Metadata {
    @DisplayName: "Nikon D850 043E"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon D850 043E MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x043e |
| Device Info Pattern | `.*Nikon.*` |
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
| Overall Deadline | 180000 | ms || Stabilization Delay | 300 | ms |
| Event Pump Delay | 100 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Nikon D850 — 45.7 MP full-frame DSLR (2017), PTP over USB
- Camera must be in MTP/PTP mode via Settings > USB Options.
- NEF raw files are large; extend ioTimeoutMs if needed.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-02-28
- **Commit**: <pending>

### Evidence Artifacts
