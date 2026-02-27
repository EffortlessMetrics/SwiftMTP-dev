# Expectation Overlays

This directory holds per-device YAML files that teach `compat-harness.py`
how to classify known differences between SwiftMTP and libmtp output.

## File naming

```
<vid>_<pid>.yml      e.g.  18d1_4ee1.yml   (Google Pixel 7)
                           04e8_6860.yml   (Samsung Galaxy S21)
                           2717_ff10.yml   (Xiaomi Mi Note 2)
```

The colon form (`18d1:4ee1.yml`) is also accepted, but the underscore form
is preferred to avoid shell-escaping issues.

---

## Format reference

```yaml
# compat/expectations/18d1_4ee1.yml
# Google Pixel 7 — VID 18d1, PID 4ee1

# ── Intentional differences ──────────────────────────────────────────────
# Diffs listed here are known, documented, and expected.  They will be
# labelled  intentional  and excluded from the "unresolved" exit-code count.
intentional_differences:
  - key: device.serial
    reason: >
      SwiftMTP privacy-redacts the device serial number; libmtp surfaces it
      verbatim.  This is intentional behaviour (see SwiftMTPCore/Privacy.swift).

  - key: device.friendly_name
    reason: >
      Pixel 7 reports two different friendly-name strings depending on
      whether ADB or MTP was the first connection since last boot.

# ── Expected failures ────────────────────────────────────────────────────
# Known bugs or limitations in ONE of the toolchains.  Use 'label' to
# indicate which side is wrong.
# Valid labels: bug_swiftmtp | bug_libmtp | quirk_needed | unknown
known_bugs:
  - key: file.DCIM/Camera
    label: bug_libmtp
    reason: >
      mtp-files omits the top-level DCIM/Camera directory on Pixel 7 when
      the storage contains more than 1 000 objects (libmtp issue #1234).

  - key: device.firmware
    label: quirk_needed
    reason: >
      Pixel 7 reports a non-standard firmware string that SwiftMTP's parser
      does not yet normalise.  A quirk entry is needed in quirks.json.

# ── Operations expected to fail on this device ───────────────────────────
# These are recorded for documentation purposes.  The harness does not
# currently match 'expected_failures' entries against diff keys, but they
# appear in meta.json for human review.
expected_failures:
  - op: GetObjectPropList
    reason: >
      Device returns a malformed prop-list for objects in the secondary
      storage when the object count exceeds 500.

# ── Tolerances ────────────────────────────────────────────────────────────
# Override the default timestamp tolerance (120 s) for this device.
# Useful for cameras that truncate timestamps to whole minutes.
tolerances:
  timestamp_seconds: 120
```

---

## Fields

### `intentional_differences`

| Field    | Type   | Description |
|----------|--------|-------------|
| `key`    | string | Diff key prefix to match (e.g. `device.serial` also matches `device.serial.anything`). |
| `reason` | string | Human-readable explanation. |

Diffs matching an entry here are labelled **`intentional`** and do **not**
count against the unresolved-diff exit code.

---

### `known_bugs`

| Field    | Type   | Description |
|----------|--------|-------------|
| `key`    | string | Diff key prefix to match. |
| `label`  | string | One of `bug_swiftmtp`, `bug_libmtp`, `quirk_needed`, `unknown`. |
| `reason` | string | Human-readable explanation, ideally with a ticket or PR reference. |

---

### `expected_failures`

| Field    | Type   | Description |
|----------|--------|-------------|
| `op`     | string | MTP operation name (e.g. `GetObjectPropList`). |
| `reason` | string | Human-readable explanation. |

These are informational only and are stored in `meta.json` for review.
They do not directly affect diff classification.

---

### `tolerances`

| Field               | Type | Description |
|---------------------|------|-------------|
| `timestamp_seconds` | int  | Maximum acceptable mtime difference in seconds (overrides `--ts-tolerance`). |

---

## Diff key format

Keys in `intentional_differences` and `known_bugs` follow this schema:

| Prefix         | Example                                      | Description |
|----------------|----------------------------------------------|-------------|
| `device.*`     | `device.manufacturer`                        | Top-level device attribute. |
| `file.<path>`  | `file.DCIM/Camera/IMG_0001.JPG`              | File presence diff (missing on one side). |
| `file.<path>.size_bytes` | `file.DCIM/Camera/IMG_0001.JPG.size_bytes` | File size mismatch. |
| `file.<path>.mtime`      | `file.DCIM/Camera/IMG_0001.JPG.mtime`      | File mtime mismatch (outside tolerance). |

Prefix matching is used: a key of `file.DCIM` matches any diff whose key
starts with `file.DCIM`.

---

## Adding a new device

1. Run the harness once without an overlay to collect raw diffs:
   ```bash
   ./scripts/compat-harness.py --vidpid <vid>:<pid>
   ```
2. Inspect `evidence/<date>/<vid>_<pid>/<run-id>/diff.md`.
3. Create `compat/expectations/<vid>_<pid>.yml` and classify each diff.
4. Re-run the harness to verify the exit code is now `0`.
5. Commit both the overlay file and the `diff.md` evidence as a PR.
