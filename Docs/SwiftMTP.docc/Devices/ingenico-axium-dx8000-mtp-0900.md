# Ingenico Axium Dx8000 Mtp 0900

@Metadata {
    @DisplayName: "Ingenico Axium Dx8000 Mtp 0900"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Ingenico Axium Dx8000 Mtp 0900 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x079b |
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

- Ingenico AXIUM DX8000 Android smart terminal.
- USB MTP for Android app sideloading and updates.
- 8-inch touchscreen with dual cameras.
- Android 10 platform for next-gen payment solutions.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
