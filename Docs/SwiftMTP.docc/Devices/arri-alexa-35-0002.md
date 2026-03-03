# Arri Alexa 35 0002

@Metadata {
    @DisplayName: "Arri Alexa 35 0002"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Arri Alexa 35 0002 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x247d |
| Product ID | 0x0002 |
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
| Maximum Chunk Size | 8.4 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 60000 | ms |
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

- ARRI ALEXA 35 Super 35mm cinema camera.
- 4.6K ALEV 4 sensor with 17 stops of dynamic range.
- USB-C data port; MTP file transfer capability unconfirmed.
- ARRI's flagship S35 camera; primary offload via Codex media.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
