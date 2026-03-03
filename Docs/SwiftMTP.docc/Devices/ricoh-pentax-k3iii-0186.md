# Ricoh Pentax K3Iii 0186

@Metadata {
    @DisplayName: "Ricoh Pentax K3Iii 0186"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Ricoh Pentax K3Iii 0186 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04f2 |
| Product ID | 0x0186 |
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
| Maximum Chunk Size | 2.1 MB | bytes |
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

- Pentax K-3 Mark III APS-C DSLR.
- 25.7MP BSI-CMOS sensor, weather-sealed magnesium body.
- PTP over USB-C for tethered shooting and file transfer.
- DNG RAW and PEF files approximately 30-40MB.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
