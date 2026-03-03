# Fujifilm X T30Ii Fw2 032A

@Metadata {
    @DisplayName: "Fujifilm X T30Ii Fw2 032A"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Fujifilm X T30Ii Fw2 032A MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04cb |
| Product ID | 0x032a |
| Device Info Pattern | `.*Fujifilm.*X-T30.*II.*` |
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

- Fujifilm X-T30 II APS-C (late firmware).
- 26.1MP X-Trans CMOS 4.
- SD card, USB-C.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
