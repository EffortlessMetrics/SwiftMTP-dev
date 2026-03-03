# Verifone V240M Mtp 0900

@Metadata {
    @DisplayName: "Verifone V240M Mtp 0900"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Verifone V240M Mtp 0900 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x11ca |
| Product ID | 0x0900 |
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

- Verifone V240m portable payment device.
- USB MTP for provisioning and log extraction.
- Compact mobile terminal with Wi-Fi and 4G.
- Color touchscreen with EMV L1/L2 certification.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
