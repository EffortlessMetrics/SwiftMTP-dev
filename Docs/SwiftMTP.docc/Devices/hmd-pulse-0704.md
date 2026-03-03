# Hmd Pulse 0704

@Metadata {
    @DisplayName: "Hmd Pulse 0704"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hmd Pulse 0704 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0421 |
| Product ID | 0x0704 |
| Device Info Pattern | `.*HMD Pulse[^+P].*` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | default | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | default | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|