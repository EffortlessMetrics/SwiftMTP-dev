# Phaseone Iq4 Achromatic 0008

@Metadata {
    @DisplayName: "Phaseone Iq4 Achromatic 0008"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phaseone Iq4 Achromatic 0008 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e70 |
| Product ID | 0x0008 |
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
| I/O Timeout | 45000 | ms |
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

- Phase One IQ4 150MP Achromatic (monochrome) digital back.
- 150MP monochrome sensor, extremely large RAW files (~200MB).
- Extended timeouts essential for reliable transfers.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
