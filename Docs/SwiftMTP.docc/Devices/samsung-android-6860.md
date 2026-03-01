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
| Status | Not Working (storage gated) |

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

## Troubleshooting

### Storage gated: GetStorageIDs returns empty list

**Symptom:** Device handshake succeeds (`Open + DeviceInfo` passes) but storage list is empty (`storageCount=0`).

**Root cause:** Samsung Android requires the user to authorize file access on the phone screen before
the MTP storage is exposed. The device is in a "locked" state where it has entered MTP mode but
not yet granted full access.

**Fix:**
1. **Unlock the phone screen** — storage access is blocked when the screen is locked.
2. **Approve the access prompt** — when connected, Samsung shows "Allow access to your files?"
   — tap **Allow**. If you missed it, check the notification shade.
3. **Unplug and replug** the USB cable after approving. The storage layer resets on reconnect.
4. Re-run `swift run --package-path SwiftMTPKit swiftmtp device-lab connected --json`.

### Handshake blocked on repeated attach

**Symptom:** `Open + DeviceInfo` fails, no recovery after reset+reopen rung.

**Possible causes:**
- Samsung's MTP daemon (`mtp-responder`) has not started. Enable file transfer mode explicitly:
  Settings → Connected devices → USB → File Transfer.
- Samsung's class 0xff vendor interface may need an extra stabilization window.
  The quirk profile uses `stabilizeMs: 500`; if you see this on slower hardware, try
  `export SWIFTMTP_STABILIZE_MS=1000`.

### Write smoke fails after storage is exposed

Samsung Galaxy S21 (`6860`) does **not** support `SendPartialObject`. Always use whole-object
writes (the default). If you see partial-write errors, verify the quirk profile is active:
```
swift run --package-path SwiftMTPKit swiftmtp quirks --vid 04e8 --pid 6860
```
The output must show `supportsSendPartialObject: false` and `disableWriteResume: true`.

## Notes

- Vendor-specific interface class (0xff) discovered by shared MTP heuristic.
- Increased post-claim stabilize to 500ms for Samsung MTP stack readiness.
- Probe ladder tries sessionless GetDeviceInfo, then OpenSession+GetDeviceInfo, then GetStorageIDs.
- Added beforeGetStorageIDs hook with busy-backoff to wait for storage readiness.
- Storage enumeration now retries up to 5 times with exponential backoff (400ms to 5s).
- Read validation is reliable; write smoke remains best-effort.
## Provenance

- **Author**: Steven Zimmerman, CPA
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
