# Lacie 1Big Dock 1084

@Metadata {
    @DisplayName: "Lacie 1Big Dock 1084"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Lacie 1Big Dock 1084 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x059f |
| Product ID | 0x1084 |
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
| Handshake Timeout | 12000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
