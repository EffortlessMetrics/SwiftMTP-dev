# Plustek Opticfilm 120 Pro 0901

@Metadata {
    @DisplayName: "Plustek Opticfilm 120 Pro 0901"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Plustek Opticfilm 120 Pro 0901 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x07b3 |
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

- Plustek OpticFilm 120 Pro medium format film scanner.
- 5300 DPI, scans 35mm through 6x12 medium format film.
- USB 2.0 for high-resolution scan transfer.
- Desktop medium format film scanner with multi-format holders.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
