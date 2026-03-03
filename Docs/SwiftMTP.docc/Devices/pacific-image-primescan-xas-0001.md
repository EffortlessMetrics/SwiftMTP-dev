# Pacific Image Primescan Xas 0001

@Metadata {
    @DisplayName: "Pacific Image Primescan Xas 0001"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Pacific Image Primescan Xas 0001 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e96 |
| Product ID | 0x0001 |
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

- Pacific Image PrimeFilm XAs 35mm film scanner.
- 10000 DPI optical resolution for 35mm film.
- USB 2.0 for scanned image transfer.
- High-resolution dedicated 35mm film and slide scanner.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
