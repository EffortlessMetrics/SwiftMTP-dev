# Pacific Image Primefilm Xa Plus 0002

@Metadata {
    @DisplayName: "Pacific Image Primefilm Xa Plus 0002"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Pacific Image Primefilm Xa Plus 0002 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e96 |
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

- Pacific Image PrimeFilm XA Plus 35mm film scanner.
- 10000 DPI with automatic batch scanning.
- USB 2.0 for scanned image transfer.
- Automatic slide feeder for batch digitization workflows.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
