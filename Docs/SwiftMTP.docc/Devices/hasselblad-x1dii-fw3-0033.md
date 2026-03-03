# Hasselblad X1Dii Fw3 0033

@Metadata {
    @DisplayName: "Hasselblad X1Dii Fw3 0033"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hasselblad X1Dii Fw3 0033 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0a17 |
| Product ID | 0x0033 |
| Device Info Pattern | `.*Hasselblad.*X1D.*II.*` |
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
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 45000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 300000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Hasselblad X1D II 50C mirrorless medium format.
- 50MP medium format in compact body.
- SD UHS-II, USB-C.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
