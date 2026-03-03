# Pax A35 Mtp 0400

@Metadata {
    @DisplayName: "Pax A35 Mtp 0400"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Pax A35 Mtp 0400 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2fb8 |
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

- PAX A35 Android countertop payment terminal.
- USB MTP for firmware and application deployment.
- 5.5-inch touchscreen with integrated printer.
- Dual SIM, Wi-Fi, and Ethernet connectivity.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
