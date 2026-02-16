# Device Bring-Up Matrix

SwiftMTP device certification should be tracked as:

`(device × mode × operation)`

This avoids binary "works/doesn't work" decisions and gives repeatable evidence for each mode.

## Quick Start

```bash
# Full bring-up with automatic artifact collection
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1

# Full bring-up with strict unlocked gate (all green checks required)
./scripts/device-bringup.sh --mode mtp-unlocked --strict-unlocked \
  --expect 04e8:6860 --expect 2717:ff40 --expect 18d1:4ee1 --expect 2a70:f003

# Quick smoke test
swift run swiftmtp --real-only probe

# Run device lab
swift run swiftmtp device-lab connected --json
```

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

### Device Collection

For contribution-ready evidence, use the collect command:

```bash
# Collect device evidence for submission
swift run swiftmtp collect --strict --noninteractive --bundle ../Contrib/submissions/my-device-bundle
```

This creates a structured bundle with probe data, USB dump, and metadata suitable for quirk submission.

## Failure Taxonomy

Connected-lab reports classify failures as:

- `class1-enumeration`: expected interfaces not exposed
- `class2-claim`: interface present but claim/access denied or busy
- `class3-handshake`: claimed link but OpenSession/GetDeviceInfo fails
- `class4-transfer`: read/write/delete fails after handshake succeeds
- `storage_gated`: session opened but `GetStorageIDs` returned zero (typically locked/unapproved Android state)

### Recovery Patterns

| Class | Recovery Strategy |
|-------|------------------|
| class1 | Check USB mode on device, try different cable/port |
| class2 | Unplug/replug, reset USB on host, check sandbox permissions |
| class3 | Add stabilization delay (postOpenSession hook), handle DEVICE_BUSY |
| class4 | Adjust timeouts, check quirk settings, try smaller chunk sizes |
| storage_gated | Unlock phone, approve file access prompt, then unplug/replug and rerun |

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
- `stabilizeMs` (if used)

## Evidence
- `Docs/benchmarks/device-bringup/<timestamp>-<mode>/`
- `Docs/benchmarks/connected-lab/<timestamp>/`
- `Contrib/submissions/<device>-bundle/`
```

## Quirks Configuration

When bringing up a new device, you may need to configure quirks in `Specs/quirks.json`:

```json
{
  "vid": "0x18d1",
  "pid": "0x4ee1",
  "description": "Device name",
  "quirks": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 20000,
    "ioTimeoutMs": 30000,
    "stabilizeMs": 2000,
    "hooks": [
      { "phase": "postOpenSession", "delayMs": 1000 }
    ]
  }
}
```

See [Device Tuning Guide](SwiftMTP.docc/DeviceTuningGuide.md) for full quirk reference.
