# Samsung Android 6860

@Metadata {
    @DisplayName("Samsung Android")
    @PageKind(article)
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
| Overall Deadline | 120000 | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- Vendor-specific interface class (0xff) discovered by shared MTP heuristic.
- Increased post-claim stabilize to 500ms for Samsung MTP stack readiness.
- Probe ladder tries sessionless GetDeviceInfo, then OpenSession+GetDeviceInfo, then GetStorageIDs.
- Added beforeGetStorageIDs hook with busy-backoff to wait for storage readiness.
- Storage enumeration now retries up to 5 times with exponential backoff (400ms to 5s).
- Read validation is reliable; write smoke remains best-effort.
## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-10
- **Commit**: (See git history for this device file)

### Evidence Artifacts
