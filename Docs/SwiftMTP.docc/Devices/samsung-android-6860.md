# Samsung Android 6860

@Metadata {
    @DisplayName: "Samsung Android 6860"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Samsung Android 6860 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04e8 |
| Product ID | 0x6860 |
| Device Info Pattern | `.*SAMSUNG.*` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Endpoints

| Property | Value |
|----------|-------|
| Input Endpoint | 0x81 |
| Output Endpoint | 0x01 |
| Event Endpoint | 0x82 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- Vendor-specific interface class (0xff) discovered by shared MTP heuristic.
- Read validation is reliable; write smoke remains best-effort for this class of Samsung devices.
- Use conservative chunking and timeout values until broader Samsung evidence is collected.
## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-09
- **Commit**: Unknown

### Evidence Artifacts
