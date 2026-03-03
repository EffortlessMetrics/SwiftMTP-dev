# Jvc Kd Mtp 0420

@Metadata {
    @DisplayName: "Jvc Kd Mtp 0420"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Jvc Kd Mtp 0420 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04f1 |
| Product ID | 0x0420 |
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
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
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

- JVC KD-series single-DIN digital media receivers.
- Compact design with USB MTP media support.
- Amazon Alexa built-in with MTP file transfer.
- Supports FLAC/WAV hi-res via MTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
