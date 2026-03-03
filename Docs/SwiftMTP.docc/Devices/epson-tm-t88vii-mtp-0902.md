# Epson Tm T88Vii Mtp 0902

@Metadata {
    @DisplayName: "Epson Tm T88Vii Mtp 0902"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Epson Tm T88Vii Mtp 0902 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b8 |
| Product ID | 0x0902 |
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

- Epson TM-T88VII next-gen thermal receipt printer.
- USB MTP for firmware and NV graphics management.
- Latest generation of the TM-T88 receipt printer series.
- 500mm/s print speed with USB-C and cloud connectivity.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
