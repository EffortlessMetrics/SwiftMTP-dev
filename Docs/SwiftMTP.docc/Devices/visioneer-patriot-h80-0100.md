# Visioneer Patriot H80 0100

@Metadata {
    @DisplayName: "Visioneer Patriot H80 0100"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Visioneer Patriot H80 0100 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a7 |
| Product ID | 0x0100 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | 0x00 |
| Protocol | 0x00 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
