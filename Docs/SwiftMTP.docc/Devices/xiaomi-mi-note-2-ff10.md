# Xiaomi Mi Note 2 Ff10

@Metadata {
    @DisplayName("Xiaomi Mi Note 2")
    @PageKind(article)
}

Device-specific configuration for Xiaomi Mi Note 2 Ff10 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2717 |
| Product ID | 0xff10 |
| Device Info Pattern | `.*Mi Note 2.*` |
| Status | Stable |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Endpoints

| Property | Value |
|----------|-------|
| Input Endpoint | 0x81 |
| Output Endpoint | 0x01 |
| Event Endpoint | 0x82 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Troubleshooting

### DEVICE_BUSY on storage operations

**Symptom:** Early storage or object list operations return `DEVICE_BUSY` (`0x2019`).

**Fix:** The quirk profile includes automatic busy-backoff. If you see repeated busy errors:
1. Increase the post-session delay: `export SWIFTMTP_POST_OPEN_DELAY_MS=600`.
2. Keep the phone screen **unlocked** during operations — screen lock causes busy responses.
3. Use a direct USB port (not a hub) to avoid enumeration delays.

### Alt-setting detection unreliable

Xiaomi Mi Note 2 uses `ff10` PID in some firmware versions and `ff40` in others.
If `probe` can't claim the interface, verify the actual PID:
```
swift run --package-path SwiftMTPKit swiftmtp usb-list | grep 2717
```
If you see `2717:ff40`, use the `xiaomi-mi-note-2-ff40` quirk profile instead.

## Notes

- Requires 250-500 ms stabilization after OpenSession.
- Prefer direct USB port; keep screen unlocked.
- Back off on DEVICE_BUSY for early storage ops.
## Provenance

- **Author**: Steven Zimmerman, CPA
- **Date**: 2025-01-09
- **Commit**: (See git history for this device file)

### Evidence Artifacts
