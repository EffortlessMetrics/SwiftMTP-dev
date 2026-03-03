# Seagate One Touch Hub 2024 Ab41

@Metadata {
    @DisplayName: "Seagate One Touch Hub 2024 Ab41"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Seagate One Touch Hub 2024 Ab41 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0bc2 |
| Product ID | 0xab41 |
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
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 100 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
