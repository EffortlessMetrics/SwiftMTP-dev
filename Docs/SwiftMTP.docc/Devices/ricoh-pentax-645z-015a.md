# Ricoh Pentax 645Z 015A

@Metadata {
    @DisplayName: "Ricoh Pentax 645Z 015A"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Ricoh Pentax 645Z 015A MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x05ca |
| Product ID | 0x015a |
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
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 240000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Pentax 645Z medium format DSLR.
- 51.4MP medium format CMOS sensor (43.8x32.8mm).
- USB 3.0 PTP for DNG/PEF RAW file transfer.
- Weather-sealed medium format body with PDAF live view.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
