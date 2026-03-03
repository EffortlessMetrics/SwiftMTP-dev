# Imaging Source Dmk Usb3 0020

@Metadata {
    @DisplayName: "Imaging Source Dmk Usb3 0020"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Imaging Source Dmk Usb3 0020 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x199e |
| Product ID | 0x0020 |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- The Imaging Source DMK 33UX USB3 monochrome camera.
- High sensitivity for NIR and UV applications.
- GenICam compliant with IC Imaging Control.
- Industrial measurement and alignment systems.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
