# Seagate Expansion Portable 2322

@Metadata {
    @DisplayName: "Seagate Expansion Portable 2322"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Seagate Expansion Portable 2322 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0bc2 |
| Product ID | 0x2322 |
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
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 300 | ms |

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
