# Epson Tm T88Vi Mtp 0901

@Metadata {
    @DisplayName: "Epson Tm T88Vi Mtp 0901"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Epson Tm T88Vi Mtp 0901 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b8 |
| Product ID | 0x0901 |
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

- Epson TM-T88VI thermal receipt printer.
- USB MTP for firmware updates and graphics deployment.
- Industry-standard POS receipt printer.
- High-speed 350mm/s thermal printing with USB and Ethernet.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
