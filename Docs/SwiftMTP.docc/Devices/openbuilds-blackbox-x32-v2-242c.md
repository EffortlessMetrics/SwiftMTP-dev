# Openbuilds Blackbox X32 V2 242C

@Metadata {
    @DisplayName: "Openbuilds Blackbox X32 V2 242C"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Openbuilds Blackbox X32 V2 242C MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1d50 |
| Product ID | 0x242c |
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

- OpenBuilds BlackBox X32 v2
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
