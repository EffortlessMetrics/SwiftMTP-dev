# Datalogic Quickscan Qd2500 Mtp 0200

@Metadata {
    @DisplayName: "Datalogic Quickscan Qd2500 Mtp 0200"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Datalogic Quickscan Qd2500 Mtp 0200 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x05f9 |
| Product ID | 0x0200 |
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

- Datalogic QuickScan QD2500 general-purpose scanner.
- USB MTP for firmware deployment and diagnostics.
- Linear and 2D imaging in compact handheld form.
- Retail and light-industrial barcode scanning.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
