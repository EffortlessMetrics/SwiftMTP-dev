# Phaseone Iq3 50Mp 0007

@Metadata {
    @DisplayName: "Phaseone Iq3 50Mp 0007"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phaseone Iq3 50Mp 0007 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e70 |
| Product ID | 0x0007 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 20000 | ms |
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

- Phase One IQ3 50MP digital back.
- PTP over USB for tethered capture and file transfer.
- RAW files around 50-60MB.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
