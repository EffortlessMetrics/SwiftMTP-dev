# Beckhoff C6015 0005

@Metadata {
    @DisplayName: "Beckhoff C6015 0005"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Beckhoff C6015 0005 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2085 |
| Product ID | 0x0005 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- Beckhoff C6015 — nano IPC. Digital signage controller. USB provisioning.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
