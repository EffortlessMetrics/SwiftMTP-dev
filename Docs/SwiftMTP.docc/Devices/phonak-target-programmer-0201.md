# Phonak Target Programmer 0201

@Metadata {
    @DisplayName: "Phonak Target Programmer 0201"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phonak Target Programmer 0201 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x20a0 |
| Product ID | 0x0201 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 66 KB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- Phonak Target Programmer — USB fitting device for Phonak Target software.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
