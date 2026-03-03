# Peloton Row Usb Export

@Metadata {
    @DisplayName: "Peloton Row Usb Export"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Peloton Row Usb Export MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0xa000 |
| Product ID | 0x0047 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
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
