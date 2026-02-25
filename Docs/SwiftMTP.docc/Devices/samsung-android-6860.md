# Samsung Android 6860

@Metadata {
    @DisplayName("Samsung Android")
    @PageKind(article)
}

Current bring-up status for Samsung Android (`VID:PID 04e8:6860`).

## Identity

| Property | Value |
|---|---|
| Vendor ID | `0x04e8` |
| Product ID | `0x6860` |
| Interface | class `0xff`, subclass `0xff`, protocol `0x00` |
| Endpoints | IN `0x81`, OUT `0x01`, EVT `0x82` |
| Quirk Profile | `samsung-android-6860` |
| Status | Experimental |

## Evidence

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Endpoints

- `Docs/benchmarks/connected-lab/20260216-015505`
- `Docs/benchmarks/connected-lab/20260216-013705`
- `Docs/benchmarks/connected-lab/20260212-053429`
- Targeted debug probe on 2026-02-16 (`SWIFTMTP_DEBUG=1 ... probe --vid 04e8 --pid 6860`)

## Modes x Operations

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 500 | ms |

| Mode | Evidence | Open + DeviceInfo | Storage IDs | Root List | Read Smoke | Write Smoke | Delete Smoke | Result |
|---|---|---|---|---|---|---|---|---|
| MTP (handshake blocked) | `20260216-015505` | Fail | N/A | N/A | Skipped | Skipped | Skipped | `class3-handshake` |
| MTP (storage gated) | `20260216-013705` | Pass | `0` storages | Fail | Skipped | Skipped | Skipped | `storage_gated` |
| MTP (storage gated) | `20260212-053429` | Pass | `0` storages | Fail | Skipped | Skipped | Skipped | `storage_gated` |
| MTP (storage exposed) | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| PTP | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Charge-only | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Transport Notes

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
- **Commit**: Unknown

### Evidence Artifacts

- Open path now attempts kernel auto-detach before claim and supports reset + reopen fallback.
- Device behavior is state-dependent: same hardware sometimes reaches open, sometimes fails at first command exchange.
- When open succeeds in current lab state, storage remains gated (`GetStorageIDs` empty), which usually indicates lock/authorization gating on Android.

## Next Validation Steps

1. Unlock and approve file access on phone, then physically replug USB.
2. Confirm transition from `storageCount=0` to `storageCount>0` in `device-lab connected` output.
3. Run write smoke only after storage is exposed; this profile uses whole-object writes.
