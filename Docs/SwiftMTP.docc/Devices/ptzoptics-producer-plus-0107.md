# Ptzoptics Producer Plus 0107

@Metadata {
    @DisplayName: "Ptzoptics Producer Plus 0107"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Ptzoptics Producer Plus 0107 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x3356 |
| Product ID | 0x0107 |
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
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- PTZOptics Producer Plus — camera controller
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
