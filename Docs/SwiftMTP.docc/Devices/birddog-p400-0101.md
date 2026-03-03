# Birddog P400 0101

@Metadata {
    @DisplayName: "Birddog P400 0101"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Birddog P400 0101 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x3355 |
| Product ID | 0x0101 |
| Device Info Pattern | `None` |
| Status | Proposed |

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
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- BirdDog P400 — full NDI PTZ, 4K60, 30x zoom
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
