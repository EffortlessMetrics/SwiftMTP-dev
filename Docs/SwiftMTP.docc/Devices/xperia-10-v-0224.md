# Xperia 10 V 0224

@Metadata {
    @DisplayName: "Xperia 10 V 0224"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Xperia 10 V 0224 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0fce |
| Product ID | 0x0224 |
| Device Info Pattern | `.*Xperia 10 V[^I].*` |
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