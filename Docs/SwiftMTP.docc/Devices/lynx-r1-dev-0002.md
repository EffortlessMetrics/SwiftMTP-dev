# Lynx R1 Dev 0002

@Metadata {
    @DisplayName: "Lynx R1 Dev 0002"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Lynx R1 Dev 0002 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x3609 |
| Product ID | 0x0002 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 15000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms |
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
