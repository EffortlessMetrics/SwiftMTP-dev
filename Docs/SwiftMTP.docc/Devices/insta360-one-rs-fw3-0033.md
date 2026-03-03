# Insta360 One Rs Fw3 0033

@Metadata {
    @DisplayName: "Insta360 One Rs Fw3 0033"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Insta360 One Rs Fw3 0033 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2e1a |
| Product ID | 0x0033 |
| Device Info Pattern | `.*Insta360.*ONE.*RS.*` |
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
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Insta360 ONE RS modular action camera (firmware v3).
- Interchangeable lens system.
- USB-C MTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
