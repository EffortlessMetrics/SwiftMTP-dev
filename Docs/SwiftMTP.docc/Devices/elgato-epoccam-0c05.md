# Elgato Epoccam 0C05

@Metadata {
    @DisplayName: "Elgato Epoccam 0C05"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Elgato Epoccam 0C05 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0fd9 |
| Product ID | 0x0c05 |
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
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Elgato EpocCam — iPhone-as-webcam USB relay
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
