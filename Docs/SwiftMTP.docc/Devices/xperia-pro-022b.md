# Xperia Pro 022B

@Metadata {
    @DisplayName: "Xperia Pro 022B"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Xperia Pro 022B MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0fce |
| Product ID | 0x022b |
| Device Info Pattern | `.*Xperia PRO[^-].*` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | default | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | default | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 350 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|