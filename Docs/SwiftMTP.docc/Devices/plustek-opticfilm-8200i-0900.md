# Plustek Opticfilm 8200I 0900

@Metadata {
    @DisplayName: "Plustek Opticfilm 8200I 0900"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Plustek Opticfilm 8200I 0900 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x07b3 |
| Product ID | 0x0900 |
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
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 30000 | ms |
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

- Plustek OpticFilm 8200i SE/Ai 35mm film scanner.
- 7200 DPI optical resolution with infrared dust removal.
- USB 2.0 for scanned image transfer.
- Affordable high-resolution 35mm film and slide scanner.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
