# Honeywell Ct60 Mtp 0400

@Metadata {
    @DisplayName: "Honeywell Ct60 Mtp 0400"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Honeywell Ct60 Mtp 0400 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0c2e |
| Product ID | 0x0400 |
| Device Info Pattern | `None` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 262 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 60000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Honeywell CT60 enterprise mobile computer.
- USB MTP for application sideloading and file transfer.
- 4.7-inch rugged Android handheld terminal.
- Integrated 1D/2D scanner for warehouse and delivery.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
