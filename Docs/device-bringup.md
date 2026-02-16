# Device Bring-Up Matrix

SwiftMTP device certification should be tracked as:

`(device × mode × operation)`

This avoids binary "works/doesn't work" decisions and gives repeatable evidence for each mode.

## Modes

Phone minimum modes:

- MTP / File Transfer
- PTP / Photo Transfer (if exposed)
- Charge only (expect "no MTP/PTP interface" guidance)
- Locked vs unlocked
- USB preference variants (for example Android "Use USB for ...")

Camera minimum modes:

- PTP
- PC Remote / Tether
- Mass storage (if exposed)

## Operations

Per mode, certify these operations:

1. Enumerate and claim interface
2. OpenSession + GetDeviceInfo
3. Storage discovery
4. Object enumeration
5. Read / download
6. Write / upload to writable target
7. Delete uploaded test object (if supported)
8. Recovery behavior (replug/retry/reset ladder)

## Repeatable Local Loop

Use the wrapper script to capture host USB truth and SwiftMTP artifacts in one folder:

```bash
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1
```

Artifacts include:

- `system_profiler SPUSBDataType` JSON
- `swiftmtp usb-dump` output
- `swiftmtp device-lab connected --json` output and per-device artifacts
- mode metadata and run summary

## Failure Taxonomy

Connected-lab reports classify failures as:

- `class1-enumeration`: expected interfaces not exposed
- `class2-claim`: interface present but claim/access denied or busy
- `class3-handshake`: claimed link but OpenSession/GetDeviceInfo fails
- `class4-transfer`: read/write/delete fails after handshake succeeds

## Device Page Template

```md
# <Device Name> (<VID:PID>)

## Summary
- Status: ✅ Working / ⚠️ Partial / ❌ Blocked
- Host: macOS <version>
- SwiftMTP: <git sha>

## Modes
| Mode | Locked? | Enumerates iface | Handshake | Read | Write | Delete | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| MTP / File transfer | Unlocked | ✅ | ✅ | ✅ | ✅ | ✅ | Baseline |
| MTP / File transfer | Locked | ✅/❌ | … | … | … | … | … |
| PTP / Photo transfer | Unlocked | ✅/❌ | … | … | … | … | … |
| Charge only | n/a | ❌ | n/a | n/a | n/a | n/a | Expected guidance |

## Known quirks
- `resetReopenOnOpenSessionIOError` (if used)
- `writeTargetLadder` (if used)

## Evidence
- `Docs/benchmarks/device-bringup/<timestamp>-<mode>/`
- `Docs/benchmarks/connected-lab/<timestamp>/`
```
