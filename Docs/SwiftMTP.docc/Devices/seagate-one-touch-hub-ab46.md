# Seagate One Touch Hub Ab46

@Metadata {
    @DisplayName: "Seagate One Touch Hub Ab46"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Seagate One Touch Hub Ab46 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0bc2 |
| Product ID | 0xab46 |
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
