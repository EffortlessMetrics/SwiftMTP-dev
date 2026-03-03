# Elo I Series 4 Mtp 0200

@Metadata {
    @DisplayName: "Elo I Series 4 Mtp 0200"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Elo I Series 4 Mtp 0200 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04e7 |
| Product ID | 0x0200 |
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
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 60000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Elo I-Series 4 interactive signage and POS display.
- USB MTP for content and firmware deployment.
- 10 to 22-inch touchscreen Android AiO computer.
- Edge-to-edge glass with multi-touch for retail kiosks.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
