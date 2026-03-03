# Insta360 Flow Pro 0026

@Metadata {
    @DisplayName: "Insta360 Flow Pro 0026"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Insta360 Flow Pro 0026 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2e1a |
| Product ID | 0x0026 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | Unknown |
| Protocol | Unknown |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
