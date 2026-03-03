# Poco M6 Pro 1022

@Metadata {
    @DisplayName: "Poco M6 Pro 1022"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Poco M6 Pro 1022 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1ebf |
| Product ID | 0x1022 |
| Device Info Pattern | `.*POCO M6 Pro.*` |
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
| Maximum Chunk Size | 2.1 MB | bytes |
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
