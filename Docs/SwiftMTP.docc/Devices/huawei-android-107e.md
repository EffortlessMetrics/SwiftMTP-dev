# Huawei Android 107E

@Metadata {
    @DisplayName: "Huawei Android 107E"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Huawei Android 107E MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x12d1 |
| Product ID | 0x107e |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | default | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
