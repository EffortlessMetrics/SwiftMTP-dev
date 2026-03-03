# Huawei Matepad Pro 132

@Metadata {
    @DisplayName: "Huawei Matepad Pro 132"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Huawei Matepad Pro 132 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0xa000 |
| Product ID | 0x0377 |
| Device Info Pattern | `None` |
| Status | Proposed |

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
