# Kodak Pixpro Fz55 0031

@Metadata {
    @DisplayName: "Kodak Pixpro Fz55 0031"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kodak Pixpro Fz55 0031 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x040a |
| Product ID | 0x0031 |
| Device Info Pattern | `.*Kodak.*PIXPRO.*FZ55.*` |
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
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Kodak PIXPRO FZ55 compact.
- 16MP, 5x zoom point-and-shoot.
- USB micro-B PTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
