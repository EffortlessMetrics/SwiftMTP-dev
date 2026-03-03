# Mamiya Dm40 4002

@Metadata {
    @DisplayName: "Mamiya Dm40 4002"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Mamiya Dm40 4002 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e70 |
| Product ID | 0x4002 |
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
| I/O Timeout | 20000 | ms |
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

- Mamiya DM40 medium format digital back (rebadged Phase One P40+).
- 40MP CCD sensor, produces large IIQ/RAW files.
- Legacy PTP implementation, may need longer handshake timeout.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
