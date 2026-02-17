# OnePlus 3T F003

@Metadata {
    @DisplayName("OnePlus 3T")
    @PageKind(article)
}

Current bring-up status for OnePlus 3T (`VID:PID 2a70:f003`).

## Identity

| Property | Value |
|---|---|
| Vendor ID | `0x2a70` |
| Product ID | `0xf003` |
| Interface | class `0x06`, subclass `0x01`, protocol `0x01` |
| Secondary Interface | Mass Storage on interface 1 (`class 0x08`) |
| Endpoints | IN `0x81`, OUT `0x01`, EVT `0x82` |
| Quirk Profile | `oneplus-3t-f003` |
| Status | Stable profile, currently unavailable in latest lab run |

## Evidence

- `Docs/benchmarks/connected-lab/20260212-053429`
- Missing from latest expected-device checks:
  - `Docs/benchmarks/connected-lab/20260216-013705`
  - `Docs/benchmarks/connected-lab/20260216-015505`

## Modes x Operations

| Mode | Evidence | Open + DeviceInfo | Storage IDs | Root List | Read Smoke | Write Smoke | Delete Smoke | Result |
|---|---|---|---|---|---|---|---|---|
| MTP (handshake blocked) | `20260212-053429` | Fail after claim | N/A | N/A | Skipped | Skipped | Skipped | `partial` (`probe-no-crash`) |
| MTP (storage exposed) | Not yet captured on current transport revision | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| PTP | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Charge-only | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Transport Notes

- This device exposes both MTP and Mass Storage interfaces; transport should always bind interface 0 (MTP).
- Quirk flags include `writeToSubfolderOnly=true` and `resetReopenOnOpenSessionIOError=true`.
- Current validation is blocked by device absence in latest attached-device runs.

## Next Validation Steps

1. Reattach device and confirm it appears in `swiftmtp usb-dump` as `2a70:f003`.
2. Run `swiftmtp device-lab connected --json` and verify open path on current reset+reopen transport.
3. Execute write smoke to a subfolder and confirm delete cleanup.
