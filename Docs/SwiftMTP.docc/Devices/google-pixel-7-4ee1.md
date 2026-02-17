# Google Pixel 7 4Ee1

@Metadata {
    @DisplayName("Google Pixel 7")
    @PageKind(article)
}

Current bring-up status for Google Pixel 7 (`VID:PID 18d1:4ee1`).

## Identity

| Property | Value |
|---|---|
| Vendor ID | `0x18d1` |
| Product ID | `0x4ee1` |
| Interface | class `0x06`, subclass `0x01`, protocol `0x01` |
| Endpoints | IN `0x81`, OUT `0x01`, EVT `0x82` |
| Quirk Profile | `google-pixel-7-4ee1` |
| Status | Experimental |

## Evidence

- `Docs/benchmarks/connected-lab/20260216-015505`
- `Docs/benchmarks/connected-lab/20260212-053429`
- Targeted debug probe on 2026-02-16 (`SWIFTMTP_DEBUG=1 ... probe --vid 18d1 --pid 4ee1`)

## Modes x Operations

| Mode | Evidence | Open + DeviceInfo | Storage IDs | Root List | Read Smoke | Write Smoke | Delete Smoke | Result |
|---|---|---|---|---|---|---|---|---|
| MTP (handshake blocked) | `20260216-015505` | Fail (claimed, then bulk OUT timeout `sent=0 rc=-7`) | N/A | N/A | Skipped | Skipped | Skipped | `class3-handshake` |
| MTP (handshake blocked) | `20260212-053429` | Fail | N/A | N/A | Skipped | Skipped | Skipped | `blocked` |
| MTP (storage exposed) | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| PTP | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Charge-only | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Transport Notes

- Reset + teardown + fresh reopen rung is now executed on first open-session I/O failure.
- For this device, the second pass still fails in the same way: OUT endpoint accepts claim but rejects first command write.
- This is now reported as a handshake failure, not an interface-discovery failure.

## Next Validation Steps

1. Unlock phone, set USB mode to File Transfer, approve access, unplug/replug.
2. Re-run `swift run --package-path SwiftMTPKit swiftmtp device-lab connected --json`.
3. If still blocked, capture a side-by-side libusb trace (`mtp-detect` vs `swiftmtp probe`) for this device state.
