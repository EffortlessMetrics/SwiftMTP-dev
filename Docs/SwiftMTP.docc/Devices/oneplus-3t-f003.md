# OnePlus 3T F003

@Metadata {
    @DisplayName("OnePlus 3T")
    @PageKind(article)
}

Current bring-up status for OnePlus 3T (`VID:PID 2a70:f003`).

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2a70 |
| Product ID | 0xf003 |
| Device Info Pattern | `None` |
| Status | Partial |

|---|---|
| Vendor ID | `0x2a70` |
| Product ID | `0xf003` |
| Interface | class `0x06`, subclass `0x01`, protocol `0x01` |
| Secondary Interface | Mass Storage on interface 1 (`class 0x08`) |
| Endpoints | IN `0x81`, OUT `0x01`, EVT `0x82` |
| Quirk Profile | `oneplus-3t-f003` |
| Status | Partial — probe works, absent from recent lab runs |

## Evidence

- `Docs/benchmarks/connected-lab/20260212-053429`
- Missing from latest expected-device checks:
  - `Docs/benchmarks/connected-lab/20260216-013705`
  - `Docs/benchmarks/connected-lab/20260216-015505`

## Modes x Operations

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 8000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |

| Mode | Evidence | Open + DeviceInfo | Storage IDs | Root List | Read Smoke | Write Smoke | Delete Smoke | Result |
|---|---|---|---|---|---|---|---|---|
| MTP (handshake blocked) | `20260212-053429` | Fail after claim | N/A | N/A | Skipped | Skipped | Skipped | `partial` (`probe-no-crash`) |
| MTP (storage exposed) | Not yet captured on current transport revision | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| PTP | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Charge-only | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Transport Notes

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Troubleshooting

### SendObject 0x201D (InvalidParameter) when uploading files

**Symptom:** `swiftmtp push` or file upload fails with error code `0x201D` (InvalidParameter).

**Root cause:** OnePlus 3T rejects `SendObject` when the parent handle is `0x00000000`
(storage root). This is a device firmware limitation, not an MTP protocol violation.

**Fix (automatic):** SwiftMTP detects this device via its quirk profile and automatically
redirects writes to the first available subfolder (`writeToSubfolderOnly=true` flag).
If you see this error, ensure the quirk profile is loaded:
```
swift run --package-path SwiftMTPKit swiftmtp quirks --vid 2a70 --pid f003
```
The output should show `writeToSubfolderOnly: true`.

**Manual workaround:** Always specify a destination folder, not the device root:
```
swift run --package-path SwiftMTPKit swiftmtp push --parent-path /DCIM/Camera myfile.jpg
```

### Large file uploads stall or timeout

If uploads > 1 MB stall, the device may be overwhelmed by the default 1 MB chunk size.
The quirk profile already sets `maxChunkBytes: 1048576`. If you still see stalls:
1. Set a smaller chunk: `export SWIFTMTP_MAX_CHUNK_BYTES=524288` and retry.
2. Increase I/O timeout: `export SWIFTMTP_IO_TIMEOUT_MS=15000` for large transfers.

### Mass Storage interface claim conflict

If `probe` fails with "access denied", Android File Transfer or macOS may have claimed
the Mass Storage interface (interface 1). The MTP transport must bind interface 0.
Quit Android File Transfer, revoke all USB authorizations on the phone, and replug.

## Notes

- OnePlus 3T (ONEPLUS A3010) probes in ~115 ms; no resetOnOpen needed with new claim sequence.
- PTP Device Reset (0x66) NOT supported (rc=-9, LIBUSB_ERROR_PIPE); skipPTPReset=true.
- Session opens instantly (0 ms), no retry needed.
- SendObject returns 0x201D (InvalidParameter) when writing to storage root; use a subfolder as parent.
- Second USB interface is Mass Storage (class=0x08); ignored by MTP transport.
- Fallback strategies: enum=propList5, read=partial64, write=partial.
## Provenance

- **Author**: Steven Zimmerman, CPA
- **Date**: 2026-02-07
- **Commit**: Unknown

### Evidence Artifacts
- [Device Probe](Docs/benchmarks/probes/oneplus3t-probe.txt)
- [USB Dump](Docs/benchmarks/probes/oneplus3t-usb-dump.txt)

- This device exposes both MTP and Mass Storage interfaces; transport should always bind interface 0 (MTP).
- Quirk flags include `writeToSubfolderOnly=true` and `resetReopenOnOpenSessionIOError=true`.
- Current validation is blocked by device absence in latest attached-device runs.

## Next Validation Steps

1. Reattach device and confirm it appears in `swiftmtp usb-dump` as `2a70:f003`.
2. Run `swiftmtp device-lab connected --json` and verify open path on current reset+reopen transport.
3. Execute write smoke to a subfolder and confirm delete cleanup.
