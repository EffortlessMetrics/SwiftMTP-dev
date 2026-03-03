# Fluke 1760 Power Recorder 0040

@Metadata {
    @DisplayName: "Fluke 1760 Power Recorder 0040"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Fluke 1760 Power Recorder 0040 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0f7e |
| Product ID | 0x0040 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | 0xff |
| Protocol | 0x00 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

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
