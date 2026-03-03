# Ingenico Desk3500 Mtp 0600

@Metadata {
    @DisplayName: "Ingenico Desk3500 Mtp 0600"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Ingenico Desk3500 Mtp 0600 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x079b |
| Product ID | 0x0600 |
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

- Ingenico Desk/3500 countertop payment terminal.
- USB MTP for firmware deployment and maintenance.
- Ethernet and dial-up connectivity with USB management.
- Compact countertop terminal with thermal printer.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
